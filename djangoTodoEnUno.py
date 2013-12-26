#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
Este script es posible gracias a la siguiente fuente:

    http://michal.karzynski.pl/blog/2013/06/09/django-nginx-gunicorn-virtualenv-supervisor/

Creado por kaotika ada_lovelance@hackingcodeschool.net

Visitanos en hackingcodeschool.net

Created on Wed Dec 25 04:00:46 2013

@author: kaotika
"""

import sys
import subprocess


DEBUG = 1
LOGFILE = "/tmp/server.log"

ORDEN_PSQL = [ "su" , "-" , "postgres" , "-c",
              "orden que quieras ejecutar"]

if not DEBUG:
    def log(cadena):
        """ Función Nula."""

        pass
else:
    def log(cadena):
        """Función encargada de escribir un log básico."""

        volcado = open(LOGFILE, "a")
        volcado.write(str(cadena) + '\n')
        volcado.close()


print "Este script configurará Django con Nginx, Gunicorn, virtualenv,\n\
supervisor y PostgreSQL, este script requiere permisos de superusuario\n\n"
print "Lo primero que se va a ejecutar es aptitude update && upgrade,\n\
es recomendable para las instalaciones posteriores\n\n"

respUdt = raw_input('Permites actualizar el sistema (s/n)')

if respUdt == 's':
    subprocess.call(['aptitude', 'update'])
    subprocess.call(['aptitude', 'upgrade'])
else:
    print "Tu sistema no se actualizará"
    exit("\nGracias por tu colaboración.\n")

print "\nAhora te preguntaremos algunos detalles más.\n"
dominio = raw_input('Introduce tu dominio ej hackingcodeschool.net : ')

respdb = \
    raw_input("Se recomienda postgres como base de datos, \n\
¿deseas instalarlo?, (s/n): ")

if respdb == 's':
    subprocess.call(['aptitude', 'install',
                    'postgresql postgresql-contrib'])

    nombredb = \
        raw_input('Introduce un nombre para tu nueva base de datos')
    usuariodb = raw_input('Introduce un usuari@ para tu base de datos: '
                          )
    passdb1 = \
        raw_input("Introduce una contraseña para tu base de datos:")
    passdb2 = raw_input("Repite tu contraseña")

    while passdb1 != passdb2:
        print "Las contraseñas introducidas no coinciden"
        passdb1 = \
            raw_input("Introduce una contraseña para tu base de datos:")
        passdb2 = raw_input("Repite tu contraseña")
    else:
        print "La contraseña ha sido almacenada correctamente"
        # Mira la lista ORDEN_PSQL al comienzo del script
        ORDEN_PSQL.append(usuariodb)
        ORDEN_PSQL.append(passdb1)
        # Ahora ejecutamos el script
        subprocess.call(ORDEN_PSQL)
else:
    sys.exit("No se ha instalado nada, pero tu sistema está actualizado.")
