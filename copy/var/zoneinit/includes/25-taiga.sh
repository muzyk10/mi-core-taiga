#!/usr/bin/env bash

TAIGA_DIR="/opt/taiga"
TAIGA_DIST_DIR="/opt/taiga_frontend"
TAIGA_HOSTNAME=$(hostname)
TAIGA_RMQ_PW=$(mdata-get taiga_rabbitmq_pw)
TAIGA_PGSQL_PW=$(mdata-get taiga_pgsql_pw)
TAIGA_SECRET_KEY=$(LC_ALL=C tr -cd '[:alnum:]' < /dev/urandom | head -c64)


log "taiga create settings/local.py"
cat > ${TAIGA_DIR}/settings/local.py <<-EOF
from .common import *

MEDIA_URL = "https://${TAIGA_HOSTNAME}/media/"
STATIC_URL = "https://${TAIGA_HOSTNAME}/static/"
SITES["front"]["scheme"] = "https"
SITES["front"]["domain"] = "${TAIGA_HOSTNAME}"

SECRET_KEY = "${TAIGA_SECRET_KEY}"

DEBUG = False
PUBLIC_REGISTER_ENABLED = True

DEFAULT_FROM_EMAIL = "no-reply@${TAIGA_HOSTNAME}"
SERVER_EMAIL = DEFAULT_FROM_EMAIL

CELERY_ENABLED = True

EVENTS_PUSH_BACKEND = "taiga.events.backends.rabbitmq.EventsPushBackend"
EVENTS_PUSH_BACKEND_OPTIONS = {"url": "amqp://taiga:${TAIGA_RMQ_PW}@localhost:5672/taiga"}

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'taiga',
        'USER': 'taiga',
        'PASSWORD': '${TAIGA_PGSQL_PW}',
        'HOST': '',
        'PORT': '',
    }
}
# Uncomment and populate with proper connection parameters
# for enable email sending. EMAIL_HOST_USER should end by @domain.tld
#EMAIL_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
#EMAIL_USE_TLS = False
#EMAIL_HOST = "localhost"
#EMAIL_HOST_USER = ""
#EMAIL_HOST_PASSWORD = ""
#EMAIL_PORT = 25
EOF

log "taiga migrate"
pushd ${TAIGA_DIR} >/dev/null
${TAIGA_DIR}/manage.py migrate --noinput
log "taiga initialise user"
${TAIGA_DIR}/manage.py loaddata initial_user
log "taiga initialise project templates"
${TAIGA_DIR}/manage.py loaddata initial_project_templates
log "taiga compile messages"
${TAIGA_DIR}/manage.py compilemessages
log "taige collect static files"
${TAIGA_DIR}/manage.py collectstatic --noinput

log "fix all permissions"
chown -R taiga:taiga ${TAIGA_DIR}
popd >/dev/null


log "create taiga dist configuration file"
cat > ${TAIGA_DIST_DIR}/conf.json <<-EOF
{
 "api": "https://${TAIGA_HOSTNAME}/api/v1/",
 "eventsUrl": "wss://${TAIGA_HOSTNAME}/events",
 "debug": "true",
 "publicRegisterEnabled": true,
 "feedbackEnabled": true,
 "privacyPolicyUrl": null,
 "termsOfServiceUrl": null,
 "GDPRUrl": null,
 "maxUploadFileSize": null,
 "contribPlugins": []
}
EOF


log "enable taiga gunicorn service"
svcadm enable svc:/network/gunicorn:taiga
