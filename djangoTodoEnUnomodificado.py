# -*- encoding: utf-8 -*-
#!/usr/bin/env python
"""
Created on Wed Dec 25 04:00:46 2013
@author: kaotika & M.
Este script es posible gracias a la siguiente fuente: http://michal.karzynski.pl/blog/2013/06/09/django-nginx-gunicorn-virtualenv-supervisor/
Creado por kaotika ada_lovelance@hackingcodeschool.net Visitanos en hackingcodeschool.net
"""

import subprocess
import os
import sys


################
#Función de debug
############

def dondeEstoy():
    print ("estás en")
    subprocess.call("pwd")
    print ("salida ls")
    subprocess.call("ls")

############################
#Actualizamos el sistema 
############################

print
print "Este script configurará Django con Nginx, Gunicorn, virtualenv, \
supervisor y PostgreSQL.\nEste script requiere permisos de superusuario."
print
print "Lo primero que se va a ejecutar es aptitude update && upgrade, \
\nes recomendable para las instalaciones posteriores."

print

respUdt = raw_input("Permites actualizar el sistema (s/n): ")

if respUdt == "s" :
    subprocess.call(["aptitude","update"])
    subprocess.call(["aptitude","upgrade"])
else:
    print "Tu sistema no se actualizará"

dominio = raw_input("Introduce tu dominio ej hackingcodeschool.net : ")

###############################
#Instalamos base de datos
##############################

respdb = raw_input(" Se recomienda postgres como base de datos, \
deseas instalarlo, s/n: \n")

if respdb == "s":

    proyect = raw_input("¿Cómo se llamá tu proyecto?:  ")
    userdb  = raw_input("\nEscribe el nombre de tu base de datos.\n \
Se te volverá a pedir con la siguiente pregunta más adelante (Da la misma repuesta):\n \
Ingrese el nombre del rol a agregar: ")

    passdb1 = raw_input("Escribe tú contraseña para la base de datos: ")
    passdb2 = raw_input("Repite la contraseña escrita para su verificación. \
Se te volverá a pedir un poco más abajo. \
Has de poner la misma contraseña en el siguiente paso: ")

    while passdb1 != passdb2:
        print "Las contraseñas introducidas no coinciden"

        passdb1 = raw_input("Escribe tú contraseña para la base de datos: ")
        passdb2 = raw_input("Repite la contraseña escrita para su verificación, \
        se te volverá a pedir un poco más abajo. \
        Has de poner la misma contraseña en el siguiente paso: ")

    else:
        subprocess.call(["aptitude","install","postgresql", "libpq-dev", "python-dev"])
        subprocess.call(["su", "-", "postgres", "-c", "createuser -r -S -e -d -E -P"])
        subprocess.call(["su", "-", "postgres", "-c", "createdb --owner " + userdb + " " + proyect ] )

else:
   print "No se instalará ninguna base de datos, continuaremos con la instalación de virtualenv"
   userdb = raw_input("Escribe el nombre de la carpeta donde se guardará tu proyecto, ej: webapps: ")
   proyect = raw_input("¿Cómo se llamará tú proyecto?: ")
   passdb1 = raw_input("Escribe la contraseña para la base de datos de este proyecto, tú settings.py será configurado con esta password\
   pero habrás de modificar la línea, databases, para que funcione con tu base de datos.")
   #print "¿Desea instalar otra base de datos?" Las opciones son: ....... esto para ampliaciones

##########################################################
#Instalamos virtualEnv
##########################################################

subprocess.call(["aptitude","install","python-virtualenv"])

############################################################
#Crearemos el directorio de trabajo y activamos el entorno
############################################################

ruta = raw_input("Escribe la ruta absoluta donde deseas que se cree tu entorno de virtualenv: ")

os.chdir(ruta)
subprocess.call(["virtualenv" , userdb])
os.chdir(userdb)
subprocess.Popen(["/bin/sh", "-c", "cd",  userdb ,  "&" ,  "~/local/virtualenv/activate" ])

######################################################
#Instalamos django y creamos el nuevo proyecto
######################################################
print "Ahora se instalará django, psycopg2 y se creará tu nuevo proyecto"

subprocess.call(["/bin/sh", "-c", "pip install django psycopg2"])
subprocess.call(["/bin/sh", "-c", "django-admin.py startproject " +  proyect])
os.chdir(proyect)

#####################################################################
#Configuracion de Settings.py con Postgrees para trabajar con django
#####################################################################

os.chdir(proyect)


def remplace(fichero, stringA, stringB):
#    Remplaza  la cadena A por la cadena B dentro de un fichero
    f = open(fichero, 'r+')
    d = f.read()
    d = d.replace(stringA, stringB)
    f.close

    otro = open(fichero, 'r+')
    otro.write(d)
    otro.close

    print  "Su línea: ", stringA ,"Ha sido remplazada por: ", stringB # "en: " , dondeEstoy()


print "Se configurará el fichero settings.py con tus cambios, a continuación se mostrarán las modificaciones"

remplace('settings.py','django.db.backends.sqlite3', 'django.db.backends.postgresql_psycopg2')
remplace('settings.py', "'NAME': os.path.join(BASE_DIR, 'db.sqlite3'),", \
"'NAME':  " + "'" + proyect + "',"\
+ "\n        'USER':  " + "'" + userdb  + "'," \
+ "\n        'PASSWORD':  " + "'" + passdb1 + "'," \
+ "\n        'HOST' : 'localhost'," \
+ "\n        'PORT': '', ")



os.chdir( ruta + "/" + userdb + "/" + proyect)
print "Ahora se sincronizará tu base de datos, y se te pedirá un usuario para acceder a django"
subprocess.call(["/bin/sh", "-c", "python manage.py syncdb"])

###################################################################
# Se crea un usuario con permisos limitados en el sistema que será
# quién lance la aplicación
###################################################################


print "Ahora se creará un usuario con permisos limitados (usuario del sistema), que será quién lance la aplicación\
      \nEl nombre de este usuario es:", userdb, "y su grupo es: ", userdb, "Esto se hace por la seguridad del sistema"


os.system("groupadd " +  "-r "  + userdb)
os.system("useradd " +  " -r " + proyect + " -g " + userdb + " -d " + "/" + ruta + "/" + userdb + "/" + proyect)

print "Usuario y grupo añadido, se continua"

#######################################################################
#Gunicorn
#Instalación
#######################################################################

print
print "Ahora se instalará gunicorn"
print "El número de puerto donde correrá su servidor gunicorn es el 8001."
cambpuer = raw_input("¿Desea cambiarlo?.  s/n: " )

if cambpuer == 'n':
    subprocess.call(["/bin/sh", "-c", "pip install gunicorn"])
    print "Si levanta ahora el servidor gunicorn el script finalizará en este punto y debe ocuparse usted del \
    resto de configuraciones incluidas gunicorn"
    levantaServer = raw_input("¿Desea levantar el server de gunicorn?, s/n: " )
    if levantaServer == 's' :
        subprocess.call(["/bin/sh", "-c", "gunicorn " + proyect + ".wsgi:application --bind " + dominio + ":8001"])
        sys.exit()
    else:
        print "Puede levantar su servidor gunicorn a la finalización del script con la siguiente instrucción: \
              gunicorn " + proyect + ".wsgi:application --bind " +  dominio + ":8001"
else:
    puerto = raw_input("Introduzca su número de puerto: ")
    subprocess.call(["/bin/sh", "-c", "pip install gunicorn"])

    print "Si levanta ahora el servidor gunicorn el script finalizará en este punto y debe ocuparse usted del \
    resto de configuraciones incluidas gunicorn"
    levantaServer = raw_input("¿Desea levantar el server de gunicorn?, s/n: " )

    if levantaServer == 's' :
        subprocess.call(["/bin/sh", "-c", "gunicorn " + proyect + ".wsgi:application --bind " + dominio + ":" + puerto])
        sys.exit()
    else:
        print "Puede levantar su servidor gunicorn a la finalización del script con la siguiente instrucción: \
               gunicorn " + proyect + ".wsgi:application --bind " +  dominio + ":" + puerto




#########################################################################
#Gunicorn Configuración
#########################################################################
print
print "Ahora se creará la configuración de gunicorn en: " + ruta + "/" + userdb + "/bin"
os.chdir(ruta + "/" + userdb + "/bin")

f = open('gunicorn_start.bash','w')
f.writelines('#!/bin/bash ')
f.writelines('\n \nNAME=' + " ' " + userdb + "_app' \n")
f.writelines('DJANGODIR=' +  ruta + "/" + userdb + "/" + proyect + "\n")
f.writelines('SOCKFILE=' + ruta + "/" + userdb + "/run/gunicorn.sock \n")
f.writelines('USER=' + proyect + "\n")
f.writelines('GROUP=' + userdb + "\n")
f.writelines('NUM_WORKERS=3 \n')
f.writelines('DJANGO_SETTINGS_MODULE=' + proyect + ".settings \n")
f.writelines('DJANGO_WSGI_MODULE=' + proyect + ".wsgi \n")


f.writelines("echo " + '"' + "Starting $NAME as `whoami`" + '"' + '\n'\
"cd $DJANGODIR \n" +  \
"source ../bin/activate \n" \
 + "export DJANGO_SETTINGS_MODULE=$DJANGO_SETTINGS_MODULE \n" \
 + "export PYTHONPATH=$DJANGODIR:$PYTHONPATH \n \n" +  \
"# Create the run directory if it doesn't exist \n" + \
"RUNDIR=$(dirname $SOCKFILE) \n" + \
"test -d $RUNDIR || mkdir -p $RUNDIR"+\

"# Start your Django Unicorn \n" + \
"# Programs meant to be run under supervisor should not daemonize themselves (do not use --daemon)\n" + \
"exec ../bin/gunicorn ${DJANGO_WSGI_MODULE}:application \n" + \
  "   --name $NAME \n" + \
  "   --workers $NUM_WORKERS\n" + \
  "   --user=$USER --group=$GROUP \n" + \
  "   --log-level=debug \n" + \
  "   --bind=unix:$SOCKFILE " )


f.close()


subprocess.call(["/bin/sh", "-c", "chown -R " +  proyect + ":users " + ruta + "/" + userdb])
subprocess.call(["/bin/sh", "-c", "chmod -R g+w " + ruta + "/" + userdb ])
subprocess.call(["/bin/sh", "-c", "usermod -a -G users `whoami`"])
subprocess.call(["/bin/sh", "-c", "chmod u+x " +  ruta + "/" + userdb + "/" + "bin/gunicorn_start.bash"])

print
print "Su servidor gunicorn ha sido configurado, se continua"

print
print "Instalando python-dev y setproctitle, podrás ver tus procesos al finalizar con el comando: ps aux"
print
subprocess.call(["aptitude", "install" , "python-dev"])
subprocess.call(["/bin/sh", "-c", "pip install setproctitle"])


################################################################################
# Instalación y configuración de Supervisor, Monitorizando tú aplicación.
###############################################################################


print "Ahora instalaremos supervisor"
print
subprocess.call(["aptitude" , "install" ,"supervisor"])

os.chdir("/etc/supervisor/conf.d")

f = open(proyect + ".conf", 'w')

f.writelines("[program:" + proyect + "] \n")
f.writelines("command = " + ruta + "/" + userdb + "/bin/gunicorn_start                  ; Command to start app \n" )
f.writelines("user=" + proyect + "                                                        ; User to run as \n")
f.writelines("stdout_logfile = " + ruta + "/" + userdb + "/logs/gunicorn_supervisor.log   ; Where to write log messages \n")
f.writelines("redirect_stderr = true                                                      ; Save stderr in the same log")

f.close()

print "Se ha creado el fichero " , proyect + ".conf en la ruta: /etc/suppervisor/conf.d"
print "Añadiendo el proyecto a supervisor..."

subprocess.call(["mkdir", "-p" , ruta + "/" + userdb + "/logs/" ])
subprocess.call(["touch" ,  ruta + "/" + userdb + "/logs/gunicorn_supervisor.log"])

print
print "Añadido, se continua"

subprocess.call(["/bin/sh", "-c", "supervisorctl reread"])
subprocess.call(["/bin/sh", "-c", "supervisorctl update"])


print "Supervirsor ha sido configurado. Puedes lanzar/parar/reiniciar tu aplicación con: supervisorctl start/stop/restart "






