#!/bin/bash


#########################################
# Setup conf
#########################################

# Set LDAP conf: ldap_search_base (ex: base=dc=mail, dc=example, dc=org)
if [ -n "$LDAP_BASE" ]; then
	sed -i "s/^ldap_search_base\s*:.*$/ldap_search_base: $LDAP_BASE/" /etc/postfix/saslauthd.conf
fi

# Set LDAP conf: ldap_filter (ex: uid=%u)
if [ -n "$LDAP_USER_FIELD" ]; then
	sed -i "s/^ldap_filter\s*:.*$/ldap_filter: $LDAP_USER_FIELD=%u/" /etc/postfix/saslauthd.conf
fi

# Set Postfix conf: virtual_mailbox_domains (ex: example.org)
if [ -n "$DOMAIN" ]; then
	sed -i "s/^virtual_mailbox_domains\s*=.*$/virtual_mailbox_domains = $DOMAIN/" /etc/postfix/main.cf
fi

# Set Postfix conf: hostname (ex: smtp.example.org)
if [ -n "$HOSTNAME" ]; then
	sed -i "s/^myhostname\s*=.*$/myhostname = $HOSTNAME/" /etc/postfix/main.cf
fi



#########################################
# Generate SSL certification
#########################################

CERT_FOLDER="/etc/ssl/localcerts"
KEY_PATH="$CERT_FOLDER/smtp.key.pem"
CSR_PATH="$CERT_FOLDER/smtp.csr.pem"
CERT_PATH="$CERT_FOLDER/smtp.cert.pem"

if [ ! -f $CERT_PATH ] || [ ! -f $KEY_PATH ]; then
	mkdir -p $CERT_FOLDER

    echo "SSL Key or certificate not found. Generating self-signed certificates"
    openssl genrsa -out $KEY_PATH

    openssl req -new -key $KEY_PATH -out $CSR_PATH \
    -subj "/CN=smtp"

    openssl x509 -req -days 3650 -in $CSR_PATH -signkey $KEY_PATH -out $CERT_PATH
fi



#############################################
# Add dependencies into the chrooted folder
#############################################

echo "Adding host configurations into postfix jail"
rm -rf /var/spool/postfix/etc
mkdir -p /var/spool/postfix/etc
cp -v /etc/hosts /var/spool/postfix/etc/hosts
cp -v /etc/services /var/spool/postfix/etc/services
cp -v /etc/resolv.conf /var/spool/postfix/etc/resolv.conf
echo "Adding name resolution tools into postfix jail"
rm -rf "/var/spool/postfix/lib"
mkdir -p "/var/spool/postfix/lib/$(uname -m)-linux-gnu"
cp -v /lib/$(uname -m)-linux-gnu/libnss_* "/var/spool/postfix/lib/$(uname -m)-linux-gnu/"



#########################################
# Start services
#########################################

function services {
	echo ""
	echo "#########################################"
	echo "$1 rsyslog"
	echo "#########################################"
	service rsyslog $1

	echo ""
	echo "#########################################"
	echo "$1 SASL"
	echo "#########################################"
	service saslauthd $1

	echo ""
	echo "#########################################"
	echo "$1 Postfix"
	echo "#########################################"
	postfix $1
}

# Set signal handlers
trap "services stop; exit 0" SIGINT SIGTERM
trap "services reload" SIGHUP

# Start services
services start

# Redirect logs to stdout
tail -F "/var/log/mail.log" &
wait $!
