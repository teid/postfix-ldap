#!/bin/bash


#########################################
# Feature functions
#########################################

function isDkimEnabled() {
    if [ -n "$DKIM_SELECTOR" ] && [ -n "$DOMAIN" ]; then
        return 0
    else
        return 1
    fi
}


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

# Set Postfix conf: smtpd_tls_key_file (ex: /etc/ssl/localcerts/smtp.key.pem)
if [ -n "$SSL_KEY_PATH" ]; then
	sed -i "s#^smtpd_tls_key_file\s*=.*\$#smtpd_tls_key_file = $SSL_KEY_PATH#" /etc/postfix/main.cf
fi

# Set Postfix conf: smtpd_tls_key_file (ex: /etc/ssl/localcerts/smtp.cert.pem)
if [ -n "$SSL_CERT_PATH" ]; then
	sed -i "s#^smtpd_tls_cert_file\s*=.*\$#smtpd_tls_cert_file = $SSL_CERT_PATH#" /etc/postfix/main.cf
fi

# Set OpenDKIM: domain
if [ -n "$DOMAIN" ]; then
	sed -i "s/^Domain\s.*$/Domain $DOMAIN/" /etc/opendkim.conf
fi

# Set OpenDKIM: selector
if [ -n "$DKIM_SELECTOR" ]; then
	sed -i "s/^Selector\s.*$/Selector $DKIM_SELECTOR/" /etc/opendkim.conf
fi


#########################################
# Enable features
#########################################

# Enable OpenDKIM
if isDkimEnabled; then
	sed -i "s/^#\s*smtpd_milters\s/smtpd_milters /" /etc/postfix/main.cf
	sed -i "s/^#\s*non_smtpd_milters\s/non_smtpd_milters /" /etc/postfix/main.cf
fi


#########################################
# Generate SSL certification
#########################################

CERT_FOLDER="/etc/ssl/localcerts"
CSR_PATH="/tmp/smtp.csr.pem"
DKIM_PRIV_KEY_PATH="$CERT_FOLDER/dkim.key.pem"
DKIM_PUBL_KEY_PATH="$CERT_FOLDER/dkim.pub.pem"

if [ -n "$SSL_KEY_PATH" ]; then
    KEY_PATH=$SSL_KEY_PATH
else
    KEY_PATH="$CERT_FOLDER/smtp.key.pem"
fi

if [ -n "$SSL_CERT_PATH" ]; then
    CERT_PATH=$SSL_CERT_PATH
else
    CERT_PATH="$CERT_FOLDER/smtp.cert.pem"
fi

# Generate self signed certificate
if [ ! -f $CERT_PATH ] || [ ! -f $KEY_PATH ]; then
    mkdir -p $CERT_FOLDER
    echo "SSL Key or certificate not found. Generating self-signed certificates"
    openssl genrsa -out $KEY_PATH
    openssl req -new -key $KEY_PATH -out $CSR_PATH \
    -subj "/CN=smtp"
    openssl x509 -req -days 3650 -in $CSR_PATH -signkey $KEY_PATH -out $CERT_PATH
fi

# Generate DKIM keys
if [ ! -f $DKIM_PRIV_KEY_PATH ]; then
    mkdir -p $CERT_FOLDER
    echo "DKIM Key not found. Generating a new one"
    openssl genrsa -out $DKIM_PRIV_KEY_PATH 1024
    openssl rsa -in $DKIM_PRIV_KEY_PATH -pubout -out $DKIM_PUBL_KEY_PATH
    chmod 400 $DKIM_PRIV_KEY_PATH
    chmod 400 $DKIM_PUBL_KEY_PATH
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

	if isDkimEnabled; then
		echo ""
		echo "#########################################"
		echo "$1 OpenDKIM"
		echo "#########################################"
		service opendkim $1
	fi

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
