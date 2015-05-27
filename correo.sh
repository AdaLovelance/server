#!/bin/bash
#Script de instalación y configuración de servidor de correo con vusers, vdomains y valias.
#ESTE SCRIPT DEBE EJECUTARSE: bash correo.sh de otro modo dará ciertos errores por incompatibilidad de sintáxis.
#Licencia GPL. K.
#Debian 7 fuente de referencia: https://library.linode.com/email/postfix/postfix2.9.6-dovecot2.0.19-mysql 

#Instalación de Mariadb
echo -n "Instalar mariadb?[s/n]: "
read respuestamaria
if [ "$respuestamaria" = "s" ]; then
	aptitude install mariadb-server
fi

# Instala postfix y dovecot con soporte para mariadb
aptitude install postfix postfix-mysql dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-mysql openssl
service postfix stop
service dovecot stop

sleep 2
#Configuración de la base de datos del correo
read -s -p "Introduzca clave de root de mariaDB: " passmariadb
echo -e "\n"

echo -e "Creando base de datos mailserver...\n"
echo "CREATE DATABASE mailserver;" | mysql -uroot -p$passmariadb

read -s -p "Invente una clave para la usuaria mailuser: " respuestamailuser
echo -e "\nCreando usuaria mailuser...\n"

#Creación de usuario de mysql y tablas en la bd
mysql -uroot -p$passmariadb << EOF
USE mailserver;
GRANT SELECT ON mailserver.* TO 'mailuser'@'127.0.0.1' IDENTIFIED BY '$respuestamailuser'; FLUSH PRIVILEGES;
CREATE TABLE mailserver.virtual_domains (`id` int(11) NOT NULL auto_increment, `name` varchar(50) NOT NULL, PRIMARY KEY (`id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8;
CREATE TABLE mailserver.virtual_users (`id` int(11) NOT NULL auto_increment, `domain_id` int(11) NOT NULL,`password` varchar(106) NOT NULL,`email` varchar(100) NOT NULL, PRIMARY KEY (`id`), UNIQUE KEY `email` (`email`),FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8;
CREATE TABLE mailserver.virtual_aliases (`id` int(11) NOT NULL auto_increment,`domain_id` int(11) NOT NULL, `source` varchar(100) NOT NULL,`destination` varchar(100) NOT NULL, PRIMARY KEY (`id`), FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8;
EOF

read -p "Introduzca nombre de dominio para su correo [ejemplo.net]: " respuestadominio
read -p "Introduzca su dirección de correo a crear [pepi@$respuestadominio]: " respuestacorreo
read -s -p "Invente una clave para $respuestacorreo: " passcorreo

#Creando dominio y cuenta de correo principal
mysql -uroot -p$passmariadb << EOF
USE mailserver;
INSERT INTO mailserver.virtual_domains(name) VALUES('$respuestadominio');
INSERT INTO mailserver.virtual_users(domain_id, password, email) VALUES('1', ENCRYPT('$passcorreo', CONCAT('\$6\$', SUBSTRING(SHA(RAND()), -16))), '$respuestacorreo');
EOF


echo -e "Generando certificado y asignación de permisos...\n"
openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=NO/ST=Denial/L=Nowhere/O=Dis/CN=$respuestadominio" -out /etc/dovecot/dovecot.pem -keyout /etc/dovecot/private/dovecot.pem
chmod o= /etc/dovecot/private/dovecot.pem
echo -e "Certificado generado\n"

#Instalación de amavis
echo "ahora instalaremos amavis para dejar hecha la configuración del mismo en los ficheros de postfix y dovecot correspondientes"
echo $respuestadominio > /etc/hostname
aptitude install amavis

### POSTFIX ################################################################################################

echo -e "Configurando Postfix\n"

mv /etc/postfix/main.cf /etc/postfix/main.cf.original

cat > /etc/postfix/main.cf <<EOF
# See /usr/share/postfix/main.cf.dist for a commented, more complete version
# Debian specific:  Specifying a file name will cause the first
# line of that file to be used as the name.  The Debian default
# is /etc/mailname.
#myorigin = /etc/mailname
smtpd_banner = $myhostname ESMTP $mail_name
biff = no

# appending .domain is the MUA's job.
append_dot_mydomain = no

# Uncomment the next line to generate "delayed mail" warnings
#delay_warning_time = 4h
readme_directory = no

# TLS parameters
#smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
#smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
#smtpd_use_tls=yes
#smtpd_tls_session_cache_database = btree:/smtpd_scache
#smtp_tls_session_cache_database = btree:/smtp_scache

smtpd_tls_cert_file=/etc/dovecot/dovecot.pem
smtpd_tls_key_file=/etc/dovecot/private/dovecot.pem
smtpd_use_tls=yes
smtpd_tls_auth_only = yes
smtp_use_tls = yes

#Enabling SMTP for authenticated users, and handing off authentication to Dovecot
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_local_domain = $respuestadominio
smtpd_sasl_security_options = noanonymous

#CONFIGURACION MANUAL DE RECHAZOS POR TELNET
disable_vrfy_command = yes
smtpd_delay_reject = yes
#smtpd_helo_required = yes
smtpd_helo_restrictions = permit_mynetworks,
     reject_non_fqdn_hostname,
     reject_invalid_hostname,
     permit

smtpd_recipient_restrictions =
   permit_sasl_authenticated,
   permit_mynetworks,

   
   reject_non_fqdn_recipient,
   reject_non_fqdn_sender,
   reject_unknown_recipient_domain,
   reject_unknown_sender_domain,
   reject_unauth_pipelining,
   reject_unauth_destination,
   
   #Bloqueo dominios sin registro inverso en el dns(afecta también a users)
   reject_unknown_reverse_client_hostname,
   
   #Rechazo helo/Elho Feos
   reject_non_fqdn_hostname,
   reject_invalid_hostname,

   #Solo recojo mails de cuentas existentes
   #reject_unverified_recipient,

   #rechazo de listas de correo negras o de spam
   reject_rbl_client list.dsbl.org,
   reject_rbl_client sbl.spamhaus.org,
   reject_rbl_client cbl.abuseat.org,
   reject_rbl_client dul.dnsbl.sorbs.net,
   reject_rbl_client sbl-xbl.spamhaus.org,
   permit
   
   #Configuro tiempos de rechazo para evitar spam
   smtpd_error_sleep_time = 1s
   smtpd_soft_error_limit = 10
   smtpd_hard_error_limit = 20

#FIN CONFIGURACIÖN MANUAL

# See /usr/share/doc/postfix/TLS_README.gz in the postfix-doc package for
# information on enabling SSL in the smtp client.
myhostname = $respuestadominio
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
myorigin = /etc/mailname
#mydestination = example.com, hostname.example.com, localhost.example.com, localhost
mydestination = localhost
relayhost = 
mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all

#Handing off local delivery to Dovecot's LMTP, and telling it where to store mail
virtual_transport = lmtp:unix:private/dovecot-lmtp

#Virtual domains, users, and aliases
virtual_mailbox_domains = mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf
virtual_mailbox_maps = mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf
virtual_alias_maps = mysql:/etc/postfix/mysql-virtual-alias-maps.cf
smtpd_sasl_security_options = noanonymous

###### OPENDKIM
milter_default_action = accept
milter_protocol = 6
smtpd_milters = inet:localhost:12345
non_smtpd_milters = inet:localhost:12345

# Amavis como filtro de contenidos en su default port
content_filter = smtp-amavis:[127.0.0.1]:10024
EOF


# creación tres archivos postfix que mapean la bd para los virtualhost

# 1. /etc/postfix/mysql-virtual-mailbox-domains.cf
cat > /etc/postfix/mysql-virtual-mailbox-domains.cf <<EOF
user = mailuser
password = $respuestamailuser
hosts = 127.0.0.1
dbname = mailserver
query = SELECT 1 FROM virtual_domains WHERE name='%s'
EOF

# 2. /etc/postfix/mysql-virtual-mailbox-maps.cf
cat > /etc/postfix/mysql-virtual-mailbox-maps.cf <<EOF
user = mailuser
password = $respuestamailuser
hosts = 127.0.0.1
dbname = mailserver
query = SELECT 1 FROM virtual_users WHERE email='%s'
EOF

# 3. /etc/postfix/mysql-virtual-alias-maps.cf
cat > /etc/postfix/mysql-virtual-alias-maps.cf <<EOF
user = mailuser
password = $respuestamailuser
hosts = 127.0.0.1
dbname = mailserver
query = SELECT destination FROM virtual_aliases WHERE source='%s'
EOF


cat > /etc/postfix/master.cf <<EOF
#
# Postfix master process configuration file.  For details on the format
# of the file, see the master(5) manual page (command: "man 5 master" or
# on-line: http://www.postfix.org/master.5.html).
#
# Do not forget to execute "postfix reload" after editing this file.
#
# ==========================================================================
# service type  private unpriv  chroot  wakeup  maxproc command + args
#               (yes)   (yes)   (yes)   (never) (100)
# ==========================================================================
smtp      inet  n       -       -       -       -       smtpd
#smtp      inet  n       -       -       -       1       postscreen
#smtpd     pass  -       -       -       -       -       smtpd
#dnsblog   unix  -       -       -       -       0       dnsblog
#tlsproxy  unix  -       -       -       -       0       tlsproxy
submission inet n       -       -       -       -       smtpd
#  -o syslog_name=postfix/submission
#  -o smtpd_tls_security_level=encrypt
#  -o smtpd_sasl_auth_enable=yes
#  -o smtpd_reject_unlisted_recipient=no
#  -o smtpd_client_restrictions=$mua_client_restrictions
#  -o smtpd_helo_restrictions=$mua_helo_restrictions
#  -o smtpd_sender_restrictions=$mua_sender_restrictions
#  -o smtpd_recipient_restrictions=
#  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
#  -o milter_macro_daemon_name=ORIGINATING
smtps     inet  n       -       -       -       -       smtpd
#  -o syslog_name=postfix/smtps
#  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
#  -o smtpd_reject_unlisted_recipient=yes
#  -o smtpd_client_restrictions=$mua_client_restrictions
#  -o smtpd_helo_restrictions=$mua_helo_restrictions
#  -o smtpd_sender_restrictions=$mua_sender_restrictions
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
#  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
#  -o milter_macro_daemon_name=ORIGINATING
#628       inet  n       -       -       -       -       qmqpd
pickup    unix  n       -       -       60      1       pickup
cleanup   unix  n       -       -       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
#qmgr     unix  n       -       n       300     1       oqmgr
tlsmgr    unix  -       -       -       1000?   1       tlsmgr
rewrite   unix  -       -       -       -       -       trivial-rewrite
bounce    unix  -       -       -       -       0       bounce
defer     unix  -       -       -       -       0       bounce
trace     unix  -       -       -       -       0       bounce
verify    unix  -       -       -       -       1       verify
flush     unix  n       -       -       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       -       -       -       smtp
relay     unix  -       -       -       -       -       smtp
#       -o smtp_helo_timeout=5 -o smtp_connect_timeout=5
showq     unix  n       -       -       -       -       showq
error     unix  -       -       -       -       -       error
retry     unix  -       -       -       -       -       error
discard   unix  -       -       -       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       -       -       -       lmtp
anvil     unix  -       -       -       -       1       anvil
scache    unix  -       -       -       -       1       scache
#
# ====================================================================
# Interfaces to non-Postfix software. Be sure to examine the manual
# pages of the non-Postfix software to find out what options it wants.
#
# Many of the following services use the Postfix pipe(8) delivery
# agent.  See the pipe(8) man page for information about ${recipient}
# and other message envelope options.
# ====================================================================
#
# maildrop. See the Postfix MAILDROP_README file for details.
# Also specify in main.cf: maildrop_destination_recipient_limit=1
#
maildrop  unix  -       n       n       -       -       pipe
  flags=DRhu user=vmail argv=/usr/bin/maildrop -d ${recipient}
#
# ====================================================================
#
# Recent Cyrus versions can use the existing "lmtp" master.cf entry.
#
# Specify in cyrus.conf:
#   lmtp    cmd="lmtpd -a" listen="localhost:lmtp" proto=tcp4
#
# Specify in main.cf one or more of the following:
#  mailbox_transport = lmtp:inet:localhost
#  virtual_transport = lmtp:inet:localhost
#
# ====================================================================
#
# Cyrus 2.1.5 (Amos Gouaux)
# Also specify in main.cf: cyrus_destination_recipient_limit=1
#
#cyrus     unix  -       n       n       -       -       pipe
#  user=cyrus argv=/cyrus/bin/deliver -e -r ${sender} -m ${extension} ${user}
#
# ====================================================================
# Old example of delivery via Cyrus.
#
#old-cyrus unix  -       n       n       -       -       pipe
#  flags=R user=cyrus argv=/cyrus/bin/deliver -e -m ${extension} ${user}
#
# ====================================================================
#
# See the Postfix UUCP_README file for configuration details.
#
uucp      unix  -       n       n       -       -       pipe
  flags=Fqhu user=uucp argv=uux -r -n -z -a$sender - $nexthop!rmail ($recipient)
#
# Other external delivery methods.
#
ifmail    unix  -       n       n       -       -       pipe
  flags=F user=ftn argv=/usr/lib/ifmail/ifmail -r $nexthop ($recipient)
bsmtp     unix  -       n       n       -       -       pipe
  flags=Fq. user=bsmtp argv=/usr/lib/bsmtp/bsmtp -t$nexthop -f$sender $recipient
scalemail-backend unix	-	n	n	-	2	pipe
  flags=R user=scalemail argv=/usr/lib/scalemail/bin/scalemail-store ${nexthop} ${user} ${extension}
mailman   unix  -       n       n       -       -       pipe
  flags=FR user=list argv=/usr/lib/mailman/bin/postfix-to-mailman.py
  ${nexthop} ${user}



#Manual
# Dovecot LDA (para que sea dovecot quien haga el delivery de los correos)
#dovecot   unix  -       n       n       -       -       pipe
# flags=DRhu user=vmail:vmail argv=/usr/lib/dovecot/deliver -d ${recipient}

# El filtro amavis con el puerto por defecto (10024)
smtp-amavis     unix    -       -       -       -       2       smtp
        -o smtp_data_done_timeout=1200
        -o smtp_send_xforward_command=yes

# El reinjection path por defecto de amavis (10025)
127.0.0.1:10025 inet n  -   -   -   -  smtpd
    -o content_filter=
    -o local_recipient_maps=
    -o relay_recipient_maps=
#    -o smtpd_restriction_classes=
#    -o smtpd_delay_reject=no
#    -o smtpd_client_restrictions=permit_mynetworks,reject
#    -o smtpd_helo_restrictions=
#    -o smtpd_sender_restrictions=
#    -o smtpd_recipient_restrictions=permit_mynetworks,reject
#    -o mynetworks_style=host
#    -o mynetworks=127.0.0.0/8
#    -o strict_rfc821_envelopes=yes
#    -o smtpd_error_sleep_time=0
#    -o smtpd_soft_error_limit=1001
#    -o smtpd_hard_error_limit=1000
#    -o smtpd_client_connection_count_limit=0
#    -o smtpd_client_connection_rate_limit=0
#    -o receive_override_options=no_header_body_checks,no_unknown_recipient_checks
EOF
echo -e "Postfix configurado\n"

# Comprobaciones
service postfix restart
#comprueba dominio
echo -e "\nComprobando mapeo base de datos, dominios virtuales, si 1, correcto:\n"
postmap -q $respuestadominio mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf
#comprueba correo
echo -e "\nComprobando mapeo base de datos, usuaria virtual, si 1, correcto:\n"
postmap -q $respuestacorreo mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf

service postfix stop


##########################################################################
# Fin de postfix. Ahora:
########################################
#DOVECOT
###########################################################################
#Necesitamos modificar 6 archivos de los cuales haremos copia primero
###########################################################################

echo -e "Configurando Dovecot\n"

echo -e "\nHaciendo backups de los archivos de dovecot...\n"

mv /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.backup
mv /etc/dovecot/conf.d/10-mail.conf /etc/dovecot/conf.d/10-mail.conf.backup
mv /etc/dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf.backup
mv /etc/dovecot/dovecot-sql.conf.ext /etc/dovecot/dovecot-sql.conf.ext.backup
mv /etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf.backup
mv /etc/dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-ssl.conf.backup

######################################
# En debian 7 aparece este error entonces se mueve 15-mailboxes y desaparece
#  Initialization failed: namespace configuration error: inbox=yes namespace missing
#####################################
mv /etc/dovecot/conf.d/15-mailboxes.conf /etc/dovecot/conf.d/15-mailboxes.conf.backup


echo -e "\nCopia finalizada\n"
echo -e "Mostrando resultados...(Si la copia se ha realizado correctamente verá 7 archivos con terminación .backup)\n"

ls /etc/dovecot/*backup
ls /etc/dovecot/conf.d/*backup

sleep 5

############################################################################
#Configuracion dovecot.conf
############################################################################

cat > /etc/dovecot/dovecot.conf <<EOF
## Dovecot configuration file
# If you're in a hurry, see http://wiki2.dovecot.org/QuickConfiguration
# "doveconf -n" command gives a clean output of the changed settings. Use it
# instead of copy&pasting files when posting to the Dovecot mailing list.
# '#' character and everything after it is treated as comments. Extra spaces
# and tabs are ignored. If you want to use either of these explicitly, put the
# value inside quotes, eg.: key = "# char and trailing whitespace  "
# Default values are shown for each setting, it's not required to uncomment
# those. These are exceptions to this though: No sections (e.g. namespace {})
# or plugin settings are added by default, they're listed only as examples.
# Paths are also just examples with the real defaults being based on configure
# options. The paths listed here are for configure --prefix=/usr
# --sysconfdir=/etc --localstatedir=/var
# Enable installed protocols
!include_try /usr/share/dovecot/protocols.d/*.protocol
protocols = imap pop3 lmtp
# A comma separated list of IPs or hosts where to listen in for connections.
# "*" listens in all IPv4 interfaces, "::" listens in all IPv6 interfaces.
# If you want to specify non-default ports or anything more complex,
# edit conf.d/master.conf.
#listen = *, ::
# Base directory where to store runtime data.
#base_dir = /var/run/dovecot/
# Name of this instance. Used to prefix all Dovecot processes in ps output.
#instance_name = dovecot
# Greeting message for clients.
#login_greeting = Dovecot ready.
# Space separated list of trusted network ranges. Connections from these
# IPs are allowed to override their IP addresses and ports (for logging and
# for authentication checks). disable_plaintext_auth is also ignored for
# these networks. Typically you'd specify your IMAP proxy servers here.
#login_trusted_networks =
# Sepace separated list of login access check sockets (e.g. tcpwrap)
#login_access_sockets =
# Show more verbose process titles (in ps). Currently shows user name and
# IP address. Useful for seeing who are actually using the IMAP processes
# (eg. shared mailboxes or if same uid is used for multiple accounts).
#verbose_proctitle = no
# Should all processes be killed when Dovecot master process shuts down.
# Setting this to "no" means that Dovecot can be upgraded without
# forcing existing client connections to close (although that could also be
# a problem if the upgrade is e.g. because of a security fix).
#shutdown_clients = yes
# If non-zero, run mail commands via this many connections to doveadm server,
# instead of running them directly in the same process.
#doveadm_worker_count = 0
# UNIX socket or host:port used for connecting to doveadm server
#doveadm_socket_path = doveadm-server
# Space separated list of environment variables that are preserved on Dovecot
# startup and passed down to all of its child processes. You can also give
# key=value pairs to always set specific settings.
#import_environment = TZ
##
## Dictionary server settings
##
# Dictionary can be used to store key=value lists. This is used by several
# plugins. The dictionary can be accessed either directly or though a
# dictionary server. The following dict block maps dictionary names to URIs
# when the server is used. These can then be referenced using URIs in format
# "proxy::<name>".
dict {
#quota = mysql:/etc/dovecot/dovecot-dict-sql.conf.ext
#expire = sqlite:/etc/dovecot/dovecot-dict-sql.conf.ext
}
# Most of the actual configuration gets included below. The filenames are
# first sorted by their ASCII value and parsed in that order. The 00-prefixes
# in filenames are intended to make it easier to understand the ordering.
!include conf.d/*.conf
# A config file can also tried to be included without giving an error if
# it's not found:
!include_try local.conf
EOF

#echo -e "Archivo /etc/dovecot/dovecot.conf creado, ahora se mostrará para comprobaciones\n"
#sleep 2
#more /etc/dovecot/dovecot.conf





###########################################################################
#Configuracion /etc/dovecot/conf.d/10-mail.conf
###########################################################################

#echo -e "Creando el archivo de configuración /etc/dovecot/conf.d/10-mail.conf...."

cat > /etc/dovecot/conf.d/10-mail.conf <<EOF
##
## Mailbox locations and namespaces
##
# Location for users' mailboxes. The default is empty, which means that Dovecot
# tries to find the mailboxes automatically. This won't work if the user
# doesn't yet have any mail, so you should explicitly tell Dovecot the full
# location.
#
# If you're using mbox, giving a path to the INBOX file (eg. /var/mail/%u)
# isn't enough. You'll also need to tell Dovecot where the other mailboxes are
# kept. This is called the "root mail directory", and it must be the first
# path given in the mail_location setting.
#
# There are a few special variables you can use, eg.:
#
#   %u - username
#   %n - user part in user@domain, same as %u if there's no domain
#   %d - domain part in user@domain, empty if there's no domain
#   %h - home directory
#
# See doc/wiki/Variables.txt for full list. Some examples:
#
#   mail_location = maildir:~/Maildir
#   mail_location = mbox:~/mail:INBOX=/var/mail/%u
#   mail_location = mbox:/var/mail/%d/%1n/%n:INDEX=/var/indexes/%d/%1n/%n
#
# <doc/wiki/MailLocation.txt>
#
mail_location = maildir:/var/mail/vhosts/%d/%n
# If you need to set multiple mailbox locations or want to change default
# namespace settings, you can do it by defining namespace sections.
#
# You can have private, shared and public namespaces. Private namespaces
# are for user's personal mails. Shared namespaces are for accessing other
# users' mailboxes that have been shared. Public namespaces are for shared
# mailboxes that are managed by sysadmin. If you create any shared or public
# namespaces you'll typically want to enable ACL plugin also, otherwise all
# users can access all the shared mailboxes, assuming they have permissions
# on filesystem level to do so.
#
# REMEMBER: If you add any namespaces, the default namespace must be added
# explicitly, ie. mail_location does nothing unless you have a namespace
# without a location setting. Default namespace is simply done by having a
# namespace with empty prefix.
#namespace {
  # Namespace type: private, shared or public
  #type = private
  # Hierarchy separator to use. You should use the same separator for all
  # namespaces or some clients get confused. '/' is usually a good one.
  # The default however depends on the underlying mail storage format.
  #separator =
  # Prefix required to access this namespace. This needs to be different for
  # all namespaces. For example "Public/".
  #prefix =
  # Physical location of the mailbox. This is in same format as
  # mail_location, which is also the default for it.
  #location =
  # There can be only one INBOX, and this setting defines which namespace
  # has it.
  #inbox = no
  # If namespace is hidden, it's not advertised to clients via NAMESPACE
  # extension. You'll most likely also want to set list=no. This is mostly
  # useful when converting from another server with different namespaces which
  # you want to deprecate but still keep working. For example you can create
  # hidden namespaces with prefixes "~/mail/", "~%u/mail/" and "mail/".
  #hidden = no
  # Show the mailboxes under this namespace with LIST command. This makes the
  # namespace visible for clients that don't support NAMESPACE extension.
  # "children" value lists child mailboxes, but hides the namespace prefix.
  #list = yes
  # Namespace handles its own subscriptions. If set to "no", the parent
  # namespace handles them (empty prefix should always have this as "yes")
  #subscriptions = yes
#}
# Example shared namespace configuration
#namespace {
  #type = shared
  #separator = /
  # Mailboxes are visible under "shared/user@domain/"
  # %%n, %%d and %%u are expanded to the destination user.
  #prefix = shared/%%u/
  # Mail location for other users' mailboxes. Note that %variables and ~/
  # expands to the logged in user's data. %%n, %%d, %%u and %%h expand to the
  # destination user's data.
  #location = maildir:%%h/Maildir:INDEX=~/Maildir/shared/%%u
  # Use the default namespace for saving subscriptions.
  #subscriptions = no
  # List the shared/ namespace only if there are visible shared mailboxes.
  #list = children
#}
# System user and group used to access mails. If you use multiple, userdb
# can override these by returning uid or gid fields. You can use either numbers
# or names. <doc/wiki/UserIds.txt>
#mail_uid =
#mail_gid =
# Group to enable temporarily for privileged operations. Currently this is
# used only with INBOX when either its initial creation or dotlocking fails.
# Typically this is set to "mail" to give access to /var/mail.
mail_privileged_group = mail
# Grant access to these supplementary groups for mail processes. Typically
# these are used to set up access to shared mailboxes. Note that it may be
# dangerous to set these if users can create symlinks (e.g. if "mail" group is
# set here, ln -s /var/mail ~/mail/var could allow a user to delete others'
# mailboxes, or ln -s /secret/shared/box ~/mail/mybox would allow reading it).
#mail_access_groups =
# Allow full filesystem access to clients. There's no access checks other than
# what the operating system does for the active UID/GID. It works with both
# maildir and mboxes, allowing you to prefix mailboxes names with eg. /path/
# or ~user/.
#mail_full_filesystem_access = no
##
## Mail processes
##
# Don't use mmap() at all. This is required if you store indexes to shared
# filesystems (NFS or clustered filesystem).
#mmap_disable = no
# Rely on O_EXCL to work when creating dotlock files. NFS supports O_EXCL
# since version 3, so this should be safe to use nowadays by default.
#dotlock_use_excl = yes
# When to use fsync() or fdatasync() calls:
#   optimized (default): Whenever necessary to avoid losing important data
#   always: Useful with e.g. NFS when write()s are delayed
#   never: Never use it (best performance, but crashes can lose data)
#mail_fsync = optimized
# Mail storage exists in NFS. Set this to yes to make Dovecot flush NFS caches
# whenever needed. If you're using only a single mail server this isn't needed.
#mail_nfs_storage = no
# Mail index files also exist in NFS. Setting this to yes requires
# mmap_disable=yes and fsync_disable=no.
#mail_nfs_index = no
# Locking method for index files. Alternatives are fcntl, flock and dotlock.
# Dotlocking uses some tricks which may create more disk I/O than other locking
# methods. NFS users: flock doesn't work, remember to change mmap_disable.
#lock_method = fcntl
# Directory in which LDA/LMTP temporarily stores incoming mails >128 kB.
#mail_temp_dir = /tmp
# Valid UID range for users, defaults to 500 and above. This is mostly
# to make sure that users can't log in as daemons or other system users.
# Note that denying root logins is hardcoded to dovecot binary and can't
# be done even if first_valid_uid is set to 0.
#first_valid_uid = 500
#last_valid_uid = 0
# Valid GID range for users, defaults to non-root/wheel. Users having
# non-valid GID as primary group ID aren't allowed to log in. If user
# belongs to supplementary groups with non-valid GIDs, those groups are
# not set.
#first_valid_gid = 1
#last_valid_gid = 0
# Maximum allowed length for mail keyword name. It's only forced when trying
# to create new keywords.
#mail_max_keyword_length = 50
# ':' separated list of directories under which chrooting is allowed for mail
# processes (ie. /var/mail will allow chrooting to /var/mail/foo/bar too).
# This setting doesn't affect login_chroot, mail_chroot or auth chroot
# settings. If this setting is empty, "/./" in home dirs are ignored.
# WARNING: Never add directories here which local users can modify, that
# may lead to root exploit. Usually this should be done only if you don't
# allow shell access for users. <doc/wiki/Chrooting.txt>
#valid_chroot_dirs =
# Default chroot directory for mail processes. This can be overridden for
# specific users in user database by giving /./ in user's home directory
# (eg. /home/./user chroots into /home). Note that usually there is no real
# need to do chrooting, Dovecot doesn't allow users to access files outside
# their mail directory anyway. If your home directories are prefixed with
# the chroot directory, append "/." to mail_chroot. <doc/wiki/Chrooting.txt>
#mail_chroot =
# UNIX socket path to master authentication server to find users.
# This is used by imap (for shared users) and lda.
#auth_socket_path = /var/run/dovecot/auth-userdb
# Directory where to look up mail plugins.
#mail_plugin_dir = /usr/lib/dovecot/modules
# Space separated list of plugins to load for all services. Plugins specific to
# IMAP, LDA, etc. are added to this list in their own .conf files.
#mail_plugins  =
##
## Mailbox handling optimizations
##
# The minimum number of mails in a mailbox before updates are done to cache
# file. This allows optimizing Dovecot's behavior to do less disk writes at
# the cost of more disk reads.
#mail_cache_min_mail_count = 0
# When IDLE command is running, mailbox is checked once in a while to see if
# there are any new mails or other changes. This setting defines the minimum
# time to wait between those checks. Dovecot can also use dnotify, inotify and
# kqueue to find out immediately when changes occur.
#mailbox_idle_check_interval = 30 secs
# Save mails with CR+LF instead of plain LF. This makes sending those mails
# take less CPU, especially with sendfile() syscall with Linux and FreeBSD.
# But it also creates a bit more disk I/O which may just make it slower.
# Also note that if other software reads the mboxes/maildirs, they may handle
# the extra CRs wrong and cause problems.
#mail_save_crlf = no
##
## Maildir-specific settings
##
# By default LIST command returns all entries in maildir beginning with a dot.
# Enabling this option makes Dovecot return only entries which are directories.
# This is done by stat()ing each entry, so it causes more disk I/O.
# (For systems setting struct dirent->d_type, this check is free and it's
# done always regardless of this setting)
#maildir_stat_dirs = no
# When copying a message, do it with hard links whenever possible. This makes
# the performance much better, and it's unlikely to have any side effects.
#maildir_copy_with_hardlinks = yes
# Assume Dovecot is the only MUA accessing Maildir: Scan cur/ directory only
# when its mtime changes unexpectedly or when we can't find the mail otherwise.
#maildir_very_dirty_syncs = no
##
## mbox-specific settings
##
# Which locking methods to use for locking mbox. There are four available:
#  dotlock: Create <mailbox>.lock file. This is the oldest and most NFS-safe
#           solution. If you want to use /var/mail/ like directory, the users
#           will need write access to that directory.
#  dotlock_try: Same as dotlock, but if it fails because of permissions or
#               because there isn't enough disk space, just skip it.
#  fcntl  : Use this if possible. Works with NFS too if lockd is used.
#  flock  : May not exist in all systems. Doesn't work with NFS.
#  lockf  : May not exist in all systems. Doesn't work with NFS.
#
# You can use multiple locking methods; if you do the order they're declared
# in is important to avoid deadlocks if other MTAs/MUAs are using multiple
# locking methods as well. Some operating systems don't allow using some of
# them simultaneously.
#mbox_read_locks = fcntl
#mbox_write_locks = dotlock fcntl
# Maximum time to wait for lock (all of them) before aborting.
#mbox_lock_timeout = 5 mins
# If dotlock exists but the mailbox isn't modified in any way, override the
# lock file after this much time.
#mbox_dotlock_change_timeout = 2 mins
# When mbox changes unexpectedly we have to fully read it to find out what
# changed. If the mbox is large this can take a long time. Since the change
# is usually just a newly appended mail, it'd be faster to simply read the
# new mails. If this setting is enabled, Dovecot does this but still safely
# fallbacks to re-reading the whole mbox file whenever something in mbox isn't
# how it's expected to be. The only real downside to this setting is that if
# some other MUA changes message flags, Dovecot doesn't notice it immediately.
# Note that a full sync is done with SELECT, EXAMINE, EXPUNGE and CHECK
# commands.
#mbox_dirty_syncs = yes
# Like mbox_dirty_syncs, but don't do full syncs even with SELECT, EXAMINE,
# EXPUNGE or CHECK commands. If this is set, mbox_dirty_syncs is ignored.
#mbox_very_dirty_syncs = no
# Delay writing mbox headers until doing a full write sync (EXPUNGE and CHECK
# commands and when closing the mailbox). This is especially useful for POP3
# where clients often delete all mails. The downside is that our changes
# aren't immediately visible to other MUAs.
#mbox_lazy_writes = yes
# If mbox size is smaller than this (e.g. 100k), don't write index files.
# If an index file already exists it's still read, just not updated.
#mbox_min_index_size = 0
##
## mdbox-specific settings
##
# Maximum dbox file size until it's rotated.
#mdbox_rotate_size = 2M
# Maximum dbox file age until it's rotated. Typically in days. Day begins
# from midnight, so 1d = today, 2d = yesterday, etc. 0 = check disabled.
#mdbox_rotate_interval = 0
# When creating new mdbox files, immediately preallocate their size to
# mdbox_rotate_size. This setting currently works only in Linux with some
# filesystems (ext4, xfs).
#mdbox_preallocate_space = no
##
## Mail attachments
##
# sdbox and mdbox support saving mail attachments to external files, which
# also allows single instance storage for them. Other backends don't support
# this for now.
# WARNING: This feature hasn't been tested much yet. Use at your own risk.
# Directory root where to store mail attachments. Disabled, if empty.
#mail_attachment_dir =
# Attachments smaller than this aren't saved externally. It's also possible to
# write a plugin to disable saving specific attachments externally.
#mail_attachment_min_size = 128k
# Filesystem backend to use for saving attachments:
#  posix : No SiS done by Dovecot (but this might help FS's own deduplication)
#  sis posix : SiS with immediate byte-by-byte comparison during saving
#  sis-queue posix : SiS with delayed comparison and deduplication
#mail_attachment_fs = sis posix
# Hash format to use in attachment filenames. You can add any text and
# variables: %{md4}, %{md5}, %{sha1}, %{sha256}, %{sha512}, %{size}.
# Variables can be truncated, e.g. %{sha256:80} returns only first 80 bits
#mail_attachment_hash = %{sha1}
EOF

#echo -e "Archivo /etc/dovecot/conf.d/10-mail.conf creado. Se mostrará para su verificación"
#echo -e "La línea que ha sido modificada es la correspondiente a mail_location = maildir:..... y mail_privileged_group = mail"

#sleep 2
#more /etc/dovecot/conf.d/10-mail.conf


#Verificamos los permisos de  /var/mail

echo "A continuación aparecerán los permisos de /var/mail que deberán ser: drwxrwsr-x 2 root mail 4096 Mar  6 15:08 /var/mail"
echo "Permisos de /var/mail"
ls -ld /var/mail

#Crearemos  el directorio /var/mail/vhosts  y una carpeta para cada dominio creado

echo -e "Creando directorio /var/mail/vhosts...\n"

mkdir -p /var/mail/vhosts/$respuestadominio

echo -e "Creado /var/mail/vhosts/$respuestadominio\n"

echo -e "Añadiendo usuaria vmail y grupo vmail con gid 5000... \n"
groupadd -g 5000 vmail
useradd -g vmail -u 5000 vmail -d /var/mail
chown -R vmail:vmail /var/mail
echo -e "Usuaria vmail creada\n"




#########################################################
# Configuración de /etc/dovecot/conf.d/10-auth.conf     #
#########################################################

#echo -e "Configurando el fichero: /etc/dovecot/conf.d/10-auth.conf.....\n"

cat > /etc/dovecot/conf.d/10-auth.conf <<EOF
##
## Authentication processes
##
# Disable LOGIN command and all other plaintext authentications unless
# SSL/TLS is used (LOGINDISABLED capability). Note that if the remote IP
# matches the local IP (ie. you're connecting from the same computer), the
# connection is considered secure and plaintext authentication is allowed.
disable_plaintext_auth = yes
# Authentication cache size (e.g. 10M). 0 means it's disabled. Note that
# bsdauth, PAM and vpopmail require cache_key to be set for caching to be used.
#auth_cache_size = 0
# Time to live for cached data. After TTL expires the cached record is no
# longer used, *except* if the main database lookup returns internal failure.
# We also try to handle password changes automatically: If user's previous
# authentication was successful, but this one wasn't, the cache isn't used.
# For now this works only with plaintext authentication.
#auth_cache_ttl = 1 hour
# TTL for negative hits (user not found, password mismatch).
# 0 disables caching them completely.
#auth_cache_negative_ttl = 1 hour
# Space separated list of realms for SASL authentication mechanisms that need
# them. You can leave it empty if you don't want to support multiple realms.
# Many clients simply use the first one listed here, so keep the default realm
# first.
#auth_realms =
# Default realm/domain to use if none was specified. This is used for both
# SASL realms and appending @domain to username in plaintext logins.
#auth_default_realm =
# List of allowed characters in username. If the user-given username contains
# a character not listed in here, the login automatically fails. This is just
# an extra check to make sure user can't exploit any potential quote escaping
# vulnerabilities with SQL/LDAP databases. If you want to allow all characters,
# set this value to empty.
#auth_username_chars = abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234567890.-_@
# Username character translations before it's looked up from databases. The
# value contains series of from -> to characters. For example "#@/@" means
# that '#' and '/' characters are translated to '@'.
#auth_username_translation =
# Username formatting before it's looked up from databases. You can use
# the standard variables here, eg. %Lu would lowercase the username, %n would
# drop away the domain if it was given, or "%n-AT-%d" would change the '@' into
# "-AT-". This translation is done after auth_username_translation changes.
#auth_username_format =
# If you want to allow master users to log in by specifying the master
# username within the normal username string (ie. not using SASL mechanism's
# support for it), you can specify the separator character here. The format
# is then <username><separator><master username>. UW-IMAP uses "*" as the
# separator, so that could be a good choice.
#auth_master_user_separator =
# Username to use for users logging in with ANONYMOUS SASL mechanism
#auth_anonymous_username = anonymous
# Maximum number of dovecot-auth worker processes. They're used to execute
# blocking passdb and userdb queries (eg. MySQL and PAM). They're
# automatically created and destroyed as needed.
#auth_worker_max_count = 30
# Host name to use in GSSAPI principal names. The default is to use the
# name returned by gethostname(). Use "$ALL" (with quotes) to allow all keytab
# entries.
#auth_gssapi_hostname =
# Kerberos keytab to use for the GSSAPI mechanism. Will use the system
# default (usually /etc/krb5.keytab) if not specified. You may need to change
# the auth service to run as root to be able to read this file.
#auth_krb5_keytab =
# Do NTLM and GSS-SPNEGO authentication using Samba's winbind daemon and
# ntlm_auth helper. <doc/wiki/Authentication/Mechanisms/Winbind.txt>
#auth_use_winbind = no
# Path for Samba's ntlm_auth helper binary.
#auth_winbind_helper_path = /usr/bin/ntlm_auth
# Time to delay before replying to failed authentications.
#auth_failure_delay = 2 secs
# Require a valid SSL client certificate or the authentication fails.
#auth_ssl_require_client_cert = no
# Take the username from client's SSL certificate, using
# X509_NAME_get_text_by_NID() which returns the subject's DN's
# CommonName.
#auth_ssl_username_from_cert = no
# Space separated list of wanted authentication mechanisms:
#   plain login digest-md5 cram-md5 ntlm rpa apop anonymous gssapi otp skey
#   gss-spnego
# NOTE: See also disable_plaintext_auth setting.
auth_mechanisms = plain login
##
## Password and user databases
##
#
# Password database is used to verify user's password (and nothing more).
# You can have multiple passdbs and userdbs. This is useful if you want to
# allow both system users (/etc/passwd) and virtual users to login without
# duplicating the system users into virtual database.
#
# <doc/wiki/PasswordDatabase.txt>
#
# User database specifies where mails are located and what user/group IDs
# own them. For single-UID configuration use "static" userdb.
#
# <doc/wiki/UserDatabase.txt>
#!include auth-deny.conf.ext
#!include auth-master.conf.ext
#!include auth-system.conf.ext
!include auth-sql.conf.ext
#!include auth-ldap.conf.ext
#!include auth-passwdfile.conf.ext
#!include auth-checkpassword.conf.ext
#!include auth-vpopmail.conf.ext
#!include auth-static.conf.ext
EOF

#echo -e "\nEl archivo /etc/dovecot/conf.d/10-auth.conf configurado \n"
#sleep 2
#more /etc/dovecot/conf.d/10-auth.conf



####################################################################################################
#Configurando el fichero /etc/dovecot/conf.d/auth-sql.conf.ext . Este fichero es de nueva creación #
####################################################################################################

#echo -e "Creando el fichero /etc/dovecot/conf.d/auth-sql.conf.ext ..... \n"

cat > /etc/dovecot/conf.d/auth-sql.conf.ext <<EOF
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/mail/vhosts/%d/%n
}
EOF

#echo -e "\nMostrando /etc/dovecot/conf.d/auth-sql.conf.ext creado..."
#sleep 2
#more /etc/dovecot/conf.d/auth-sql.conf.ext




######################################################
#Creando fichero /etc/dovecot/dovecot-sql.conf.ext   #
######################################################

echo -e "Creando fichero /etc/dovecot/dovecot-sql.conf.ext...\n"

cat > /etc/dovecot/dovecot-sql.conf.ext <<EOF
# This file is opened as root, so it should be owned by root and mode 0600.
#
# http://wiki2.dovecot.org/AuthDatabase/SQL
#
# For the sql passdb module, you'll need a database with a table that
# contains fields for at least the username and password. If you want to
# use the user@domain syntax, you might want to have a separate domain
# field as well.
#
# If your users all have the same uig/gid, and have predictable home
# directories, you can use the static userdb module to generate the home
# dir based on the username and domain. In this case, you won't need fields
# for home, uid, or gid in the database.
#
# If you prefer to use the sql userdb module, you'll want to add fields
# for home, uid, and gid. Here is an example table:
#
# CREATE TABLE users (
#     username VARCHAR(128) NOT NULL,
#     domain VARCHAR(128) NOT NULL,
#     password VARCHAR(64) NOT NULL,
#     home VARCHAR(255) NOT NULL,
#     uid INTEGER NOT NULL,
#     gid INTEGER NOT NULL,
#     active CHAR(1) DEFAULT 'Y' NOT NULL
# );
# Database driver: mysql, pgsql, sqlite
driver = mysql
# Database connection string. This is driver-specific setting.
#
# HA / round-robin load-balancing is supported by giving multiple host
# settings, like: host=sql1.host.org host=sql2.host.org
#
# pgsql:
#   For available options, see the PostgreSQL documention for the
#   PQconnectdb function of libpq.
#   Use maxconns=n (default 5) to change how many connections Dovecot can
#   create to pgsql.
#
# mysql:
#   Basic options emulate PostgreSQL option names:
#     host, port, user, password, dbname
#
#   But also adds some new settings:
#     client_flags        - See MySQL manual
#     ssl_ca, ssl_ca_path - Set either one or both to enable SSL
#     ssl_cert, ssl_key   - For sending client-side certificates to server
#     ssl_cipher          - Set minimum allowed cipher security (default: HIGH)
#     option_file         - Read options from the given file instead of
#                           the default my.cnf location
#     option_group        - Read options from the given group (default: client)
#
#   You can connect to UNIX sockets by using host: host=/var/run/mysql.sock
#   Note that currently you can't use spaces in parameters.
#
# sqlite:
#   The path to the database file.
#
# Examples:
#   connect = host=192.168.1.1 dbname=users
#   connect = host=sql.example.com dbname=virtual user=virtual password=blarg
#   connect = /etc/dovecot/authdb.sqlite
#
connect = host=127.0.0.1 dbname=mailserver user=mailuser password=$respuestamailuser
# Default password scheme.
#
# List of supported schemes is in
# http://wiki2.dovecot.org/Authentication/PasswordSchemes
#
default_pass_scheme = SHA512-CRYPT
# passdb query to retrieve the password. It can return fields:
#   password - The user's password. This field must be returned.
#   user - user@domain from the database. Needed with case-insensitive lookups.
#   username and domain - An alternative way to represent the "user" field.
#
# The "user" field is often necessary with case-insensitive lookups to avoid
# e.g. "name" and "nAme" logins creating two different mail directories. If
# your user and domain names are in separate fields, you can return "username"
# and "domain" fields instead of "user".
#
# The query can also return other fields which have a special meaning, see
# http://wiki2.dovecot.org/PasswordDatabase/ExtraFields
#
# Commonly used available substitutions (see http://wiki2.dovecot.org/Variables
# for full list):
#   %u = entire user@domain
#   %n = user part of user@domain
#   %d = domain part of user@domain
#
# Note that these can be used only as input to SQL query. If the query outputs
# any of these substitutions, they're not touched. Otherwise it would be
# difficult to have eg. usernames containing '%' characters.
#
# Example:
#   password_query = SELECT userid AS user, pw AS password \
#     FROM users WHERE userid = '%u' AND active = 'Y'
#
#password_query = \
#  SELECT username, domain, password \
#  FROM users WHERE username = '%n' AND domain = '%d'
password_query = SELECT email as user, password FROM virtual_users WHERE email='%u';
# userdb query to retrieve the user information. It can return fields:
#   uid - System UID (overrides mail_uid setting)
#   gid - System GID (overrides mail_gid setting)
#   home - Home directory
#   mail - Mail location (overrides mail_location setting)
#
# None of these are strictly required. If you use a single UID and GID, and
# home or mail directory fits to a template string, you could use userdb static
# instead. For a list of all fields that can be returned, see
# http://wiki2.dovecot.org/UserDatabase/ExtraFields
#
# Examples:
#   user_query = SELECT home, uid, gid FROM users WHERE userid = '%u'
#   user_query = SELECT dir AS home, user AS uid, group AS gid FROM users where userid = '%u'
#   user_query = SELECT home, 501 AS uid, 501 AS gid FROM users WHERE userid = '%u'
#
#user_query = \
#  SELECT home, uid, gid \
#  FROM users WHERE username = '%n' AND domain = '%d'
# If you wish to avoid two SQL lookups (passdb + userdb), you can use
# userdb prefetch instead of userdb sql in dovecot.conf. In that case you'll
# also have to return userdb fields in password_query prefixed with "userdb_"
# string. For example:
#password_query = \
#  SELECT userid AS user, password, \
#    home AS userdb_home, uid AS userdb_uid, gid AS userdb_gid \
#  FROM users WHERE userid = '%u'
# Query to get a list of all usernames.
#iterate_query = SELECT username AS user FROM users
EOF

#echo -e "Mostrando el fichero recién configurado"
#sleep 4
#more /etc/dovecot/dovecot-sql.conf.ext

#########################################################################
#                                                                       #
#Cambiamos el dueño del grupo /etc/dovecot a nuestro usuari@ vmail      #
#                                                                       #
#########################################################################

chown -R vmail:dovecot /etc/dovecot
chmod -R o-rwx /etc/dovecot

echo -e "Permisos de /etc/dovecot cambiados\n"



##############################################################################
#                                                                            #
#Configuramos el fichero /etc/dovecot/conf.d/10-master.conf                  #
#                                                                            #
##############################################################################


#echo -e "Configurando archivo /etc/dovecot/conf.d/10-master.conf ..... \n"

cat > /etc/dovecot/conf.d/10-master.conf <<EOF
#default_process_limit = 100
#default_client_limit = 1000
# Default VSZ (virtual memory size) limit for service processes. This is mainly
# intended to catch and kill processes that leak memory before they eat up
# everything.
#default_vsz_limit = 256M
# Login user is internally used by login processes. This is the most untrusted
# user in Dovecot system. It shouldn't have access to anything at all.
#default_login_user = dovenull
# Internal user is used by unprivileged processes. It should be separate from
# login user, so that login processes can't disturb other processes.
#default_internal_user = dovecot
service imap-login {
  inet_listener imap {
    port = 0
  }
  inet_listener imaps {
    #port = 993
    #ssl = yes
  }
  # Number of connections to handle before starting a new process. Typically
  # the only useful values are 0 (unlimited) or 1. 1 is more secure, but 0
  # is faster. <doc/wiki/LoginProcess.txt>
  #service_count = 1
  # Number of processes to always keep waiting for more connections.
  #process_min_avail = 0
  # If you set service_count=0, you probably need to grow this.
  #vsz_limit = 64M
}
service pop3-login {
  inet_listener pop3 {
    port = 0
  }
  inet_listener pop3s {
    #port = 995
    #ssl = yes
  }
}
service lmtp {
 unix_listener /var/spool/postfix/private/dovecot-lmtp {
   mode = 0600
   user = postfix
   group = postfix
  }
  # Create inet listener only if you can't use the above UNIX socket
  #inet_listener lmtp {
    # Avoid making LMTP visible for the entire internet
    #address =
    #port =
  #}
}
service imap {
  # Most of the memory goes to mmap()ing files. You may need to increase this
  # limit if you have huge mailboxes.
  #vsz_limit = 256M
  # Max. number of IMAP processes (connections)
  #process_limit = 1024
}
service pop3 {
  # Max. number of POP3 processes (connections)
  #process_limit = 1024
}
service auth {
  # auth_socket_path points to this userdb socket by default. It's typically
  # used by dovecot-lda, doveadm, possibly imap process, etc. Its default
  # permissions make it readable only by root, but you may need to relax these
  # permissions. Users that have access to this socket are able to get a list
  # of all usernames and get results of everyone's userdb lookups.
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }
  unix_listener auth-userdb {
    mode = 0600
    user = vmail
    #group = vmail
  }
  # Postfix smtp-auth
  #unix_listener /var/spool/postfix/private/auth {
  #  mode = 0666
  #}
  # Auth process is run as this user.
  user = dovecot
}
service auth-worker {
  # Auth worker process is run as root by default, so that it can access
  # /etc/shadow. If this isn't necessary, the user should be changed to
  # $default_internal_user.
  user = vmail
}
service dict {
  # If dict proxy is used, mail processes should have access to its socket.
  # For example: mode=0660, group=vmail and global mail_access_groups=vmail
  unix_listener dict {
    #mode = 0600
    #user =
    #group =
  }
}
EOF

#echo -e "Mostrando la configuración del archivo recién creado /etc/dovecot/conf.d/10-master.conf ..\n"
#sleep 2
#more /etc/dovecot/conf.d/10-master.conf

echo -e "A continuación se mostrará si los certificados se han creado correctamente...\n"

ls /etc/dovecot/dovecot.pem
ls /etc/dovecot/private/dovecot.pem

#########################################################################
#                                                                       #
#Configurando el archivo /etc/dovecot/conf.d/10-ssl.conf                #
#                                                                       #
#########################################################################


#echo -e "Creando archivo /etc/dovecot/conf.d/10-ssl.conf....\n"

cat > /etc/dovecot/conf.d/10-ssl.conf <<EOF
##
## SSL settings
##
# SSL/TLS support: yes, no, required. <doc/wiki/SSL.txt>
ssl = required
# PEM encoded X.509 SSL/TLS certificate and private key. They're opened before
# dropping root privileges, so keep the key file unreadable by anyone but
# root. Included doc/mkcert.sh can be used to easily generate self-signed
# certificate, just make sure to update the domains in dovecot-openssl.cnf
ssl_cert = </etc/dovecot/dovecot.pem
ssl_key = </etc/dovecot/private/dovecot.pem
# If key file is password protected, give the password here. Alternatively
# give it when starting dovecot with -p parameter. Since this file is often
# world-readable, you may want to place this setting instead to a different
# root owned 0600 file by using ssl_key_password = <path.
#ssl_key_password =
# PEM encoded trusted certificate authority. Set this only if you intend to use
# ssl_verify_client_cert=yes. The file should contain the CA certificate(s)
# followed by the matching CRL(s). (e.g. ssl_ca = </etc/ssl/certs/ca.pem)
#ssl_ca =
# Request client to send a certificate. If you also want to require it, set
# auth_ssl_require_client_cert=yes in auth section.
#ssl_verify_client_cert = no
# Which field from certificate to use for username. commonName and
# x500UniqueIdentifier are the usual choices. You'll also need to set
# auth_ssl_username_from_cert=yes.
#ssl_cert_username_field = commonName
# How often to regenerate the SSL parameters file. Generation is quite CPU
# intensive operation. The value is in hours, 0 disables regeneration
# entirely.
#ssl_parameters_regenerate = 168
# SSL ciphers to use
#ssl_cipher_list = ALL:!LOW:!SSLv2:!EXP:!aNULL
EOF

#echo -e "Mostrando fichero recién configurado:  \n "

#more /etc/dovecot/conf.d/10-ssl.conf

##############################################################################
# define la dirección de postmaster
#############################################################################

sed -i "s|#postmaster_address =|postmaster_address = $respuestacorreo|g" /etc/dovecot/conf.d/15-lda.conf

echo -e "Dovecot configurado\n"

echo -e "Postfix+Dovecot+MariaDB han sido configurados. Comenzamos\n"

service dovecot restart
service postfix restart

echo -e "Fuente: https://library.linode.com/email/postfix/postfix2.9.6-dovecot2.0.19-mysql"
