# -*- encoding: utf-8 -*-
#!/usr/bin/env python
"""
Created on Wed Dec 25 04:00:46 2013
@author: Kaotika & M. & L.
Este script es posible gracias a la siguiente fuente: http://michal.karzynski.pl/blog/2013/06/09/django-nginx-gunicorn-virtualenv-supervisor/
Creado por Kaotika ada_lovelance@hackingcodeschool.net Visitanos en hackingcodeschool.net
"""

import subprocess
import os
import sys
import re

##################
#Función de debug
##################

def dondeEstoy():
    print ("estás en")
    subprocess.call("pwd")
    print ("salida ls")
    subprocess.call("ls")


############################
#Actualizamos el sistema 
############################

print "Este script configurará Django con Nginx, Gunicorn, virtualenv \ ,
       supervisor y PostgreSQL. \n Este script requiere permisos de superusuario"
print "Lo primero que se va a ejecutar es aptitude update && upgrade \ ,
       es recomendable para las instalaciones posteriores"

respUdt = raw_input("Permites actualizar el sistema (s/n)")

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

    userdb  = raw_input(" \nEscribe el nombre de tu base de datos.\n \
Se te volverá a pedir con la siguiente pregunta más adelante (Da la misma repuesta):\n \
Ingrese el nombre del rol a agregar: ")

    passdb1 = raw_input("Escribe tú contraseña para la base de datos: ")
    passdb2 = raw_input("Repite la contraseña escrita para su verificación. \
Se te volverá a pedir un poco más abajo. \
Has de poner la misma contraseña en el siguiente paso: ")

    else:
        subprocess.call(["aptitude","install","postgresql", "libpq-dev", "python-dev"])
        subprocess.call(["su", "-", "postgres" , "-c" , "createuser -r -S -d -e  -E -P" ] )
        #subprocess.call(["createdb","userdb","nombredb"]) 
else:
   print "No se instalará ninguna base de datos, continuaremos con la instalación de virtualenv"
   #print "¿Desea instalar otra base de datos?" Las opciones son: ....... esto para ampliaciones


############################################################
#Crearemos el directorio de trabajo y activamos el entorno
############################################################


ruta = raw_input("Escribe la ruta absoluta donde deseas que se cree tu entorno de virtualenv: ")

os.chdir(ruta)

dirApp = raw_input("¿Cómo deseas que se llame el directorio que alojará tú aplicación?: ")
subprocess.call(["virtualenv" , dirApp])

os.chdir(dirApp)

subprocess.Popen(["/bin/sh", "-c", "cd",  dirApp ,  "&" ,  "~/local/virtualenv/activate" ])

######################################################
#Instalamos django y creamos el nuevo proyecto
######################################################

print "Ahora se instalará django, psycopg2 y se creará tu nuevo proyecto"

subprocess.call(["/bin/sh", "-c", "pip install django psycopg2"])
nomApp = raw_input("¿Cómo deseas que se llame tu aplicación: ")
subprocess.call(["/bin/sh", "-c", "django-admin.py startproject " +  nomApp])
os.chdir(nomApp)

#####################################################################
#Configuracion de Settings.py con Postgrees para trabajar con django
#####################################################################

os.chdir(nomApp)


def remplace(fichero, stringA, stringB):
    """
    Remplaza  la cadena A por la cadena B dentro de un fichero
    """

    f = open(fichero, 'r+')
    d = f.read()
    d = d.replace(stringA, stringB)
    f.close

    otro = open(fichero, 'r+')
    otro.write(d)
    otro.close

    print  "Su línea: ", stringA ,"Ha sido remplazada por: ", stringB , "en: " , dondeEstoy()




print "Se configurará el fichero settings.py con tus cambios, a continuación se mostrarán las modificaciones"


remplace('settings.py','django.db.backends.sqlite3', 'django.db.backends.postgresql_psycopg2')
remplace('settings.py',"'NAME': os.path.join(BASE_DIR, 'db.sqlite3'),","'NAME':  " + nomApp + " \n
     'USER':  " + userdb + " \n'PASSWORD':  " + passdb1 + " \n 'HOST' : 'localhost',  'PORT': '', ")

