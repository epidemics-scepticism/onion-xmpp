#!/bin/bash
# Heavily based on https://gist.github.com/xnyhps/33f7de50cf91a70acf93
# With assistance from #nottor @ oftc
# onion map from https://github.com/nickcalyx/xmpp-onion-map/blob/master/onions-map.lua

if [[ $UID != "0" ]]; then
	echo "This script requires root permissions to run."
	exit 1
fi

CODENAME="$(lsb_release -sc)"

if [[ -z $CODENAME ]]; then
	echo "This script is intended for use on Debian systems."
	exit 1
fi

if [[ "$CODENAME" != "jessie" ]]; then
	echo "Here be dragons. This is intended for jessie. Bailing out, it might work for you but be warned. Remove this check to proceed."
	exit 1
fi

# Add prosody repo
cat >> /etc/apt/sources.list << EOF
deb http://packages.prosody.im/debian $CODENAME main
EOF
wget https://prosody.im/files/prosody-debian-packages.key -O- | apt-key add -
apt-get update
apt-get -y install prosody tor lua-bitop lua-sec

# Stop prosody, we're going to nuke it's config from orbit anyway
service stop prosody

# Append our hidden service config to torrc
cat >> /etc/tor/torrc << EOF
HiddenServiceDir /var/lib/tor/onion_xmpp/
HiddenServicePort 5222 127.0.0.1:5222
HiddenServicePort 5269 127.0.0.1:5269
EOF

# Reload tor, generate and fetch our onion hostname
service tor reload
SERVER_HOSTNAME=`cat /var/lib/tor/onion_xmpp_server/hostname`

# Fetch mod_onions for prosody
# TODO: how2update?
wget -O "/usr/lib/prosody/modules/mod_onions.lua" "https://hg.prosody.im/prosody-modules/raw-file/tip/mod_onions/mod_onions.lua"

# Add self-signed certs, ChatSecure and others complain without TLS.
openssl req -sha256 -x509 -nodes -days 365 -subj "/C=US/ST=Fear/L=Loathing/CN=$SERVER_HOSTNAME" -newkey rsa:2048 -keyout "/etc/prosody/certs/$SERVER_HOSTNAME.key" -out "/etc/prosody/certs/$SERVER_HOSTNAME.crt"
CERT_FP=`openssl x509 -in $SERVER_HOSTNAME.crt -noout -fingerprint -sha256 | sed 's/.*Fingerprint=//;s/://g'`

# Add our onion as VirtualHost to our prosody config, set it to only talk to other onions.
cat > /etc/prosody/prosody.cfg.lua << EOF
modules_enabled = {
		"roster";
		"tls";
		"dialback";
		"posix";
		"ping";
};
c2s_require_encryption = true;
s2s_secure_auth = false;
pidfile = "/var/run/prosody/prosody.pid";
authentication = "internal_hashed";
interfaces = { "127.0.0.1" };
VirtualHost "$SERVER_HOSTNAME"
	modules_enabled = { "onions"; };
	onions_only = true;
	onions_map = {
		["jabber.calyxinstitute.org"] = "ijeeynrc6x2uy5ob.onion";
		["riseup.net"] = "4cjw6cwpeaeppfqz.onion";
		["jabber.otr.im"] = "5rgdtlawqkcplz75.onion";
		["jabber.systemli.org"] = "x5tno6mwkncu5m3h.onion";
		["securejabber.me"] = "giyvshdnojeivkom.onion";
		["so36.net"] = "s4fgy24e2b5weqdb.onion";
		["autistici.org"] = "wi7qkxyrdpu5cmvr.onion";
		["inventati.org"] = "wi7qkxyrdpu5cmvr.onion";
		["jabber.ipredator.se"] = "3iffdebkzzkpgipa.onion";
		["cloak.dk"] = "m2dsl4banuimpm6c.onion";
		["im.koderoot.net"] = "ihkw7qy3tok45dun.onion";
		["anonymitaet-im-inter.net"] = "rwf5skuv5vqzcdit.onion";
		["jabber.ccc.de"] = "okj7xc6j2szr2y75.onion";
	};
	ssl = {
		key = "/etc/prosody/certs/$SERVER_HOSTNAME.key";
		certificate = "/etc/prosody/certs/$SERVER_HOSTNAME.crt";
	}
EOF

# Restart prosody
service prosody start

# Create initial user account
cat << EOF
We need a username for your account, eg "bob", "alice" or "charlene"
Please enter your desired username:
EOF

read DESIRED_USERNAME
DESIRED_USERNAME=`echo $DESIRED_USERNAME | sed 's:@.*::'`
prosodyctl adduser $DESIRED_USERNAME@$SERVER_HOSTNAME
cat << EOF
Configure your xmpp client with:
username/jid: $DESIRED_USERNAME@$SERVER_HOSTNAME

the SHA256 fingerprint of the servers certificate should be:
$CERT_FP

Please report or provide patches for any bugs.
EOF
