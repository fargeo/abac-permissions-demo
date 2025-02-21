#!/bin/bash

# APP and npm folder locations
# ${WEB_ROOT} and ${ARCHES_ROOT} is defined in the Dockerfile, ${ARCHES_PROJECT} in env_file.env
if [[ -z ${ARCHES_PROJECT} ]]; then
	APP_FOLDER=${ARCHES_ROOT}
	PACKAGE_JSON_FOLDER=${ARCHES_ROOT}
else
	APP_FOLDER=${WEB_ROOT}/${ARCHES_PROJECT_ROOT_DIRECTORY}
	PACKAGE_JSON_FOLDER=${ARCHES_ROOT}
fi

# npm_MODULES_FOLDER=${PACKAGE_JSON_FOLDER}/$(awk \
# 	-F '--install.modules-folder' '{print $2}' ${PACKAGE_JSON_FOLDER}/.npmrc \
# 	| awk '{print $1}' \
# 	| tr -d $'\r' \
# 	| tr -d '"' \
# 	| sed -e "s/^\.\///g")

# Environmental Variables
export DJANGO_PORT=${DJANGO_PORT:-8000}

#Utility functions that check db status
wait_for_db() {
	echo "Testing if database server is up..."
	while [[ ! ${return_code} == 0 ]]
	do
        psql --host=${PGHOST} --port=${PGPORT} --user=${PGUSERNAME} --dbname=postgres -c "select 1" >&/dev/null
		return_code=$?
		sleep 1
	done
	echo "Database server is up"

    echo "Testing if Elasticsearch is up..."
    while [[ ! ${return_code} == 0 ]]
    do
        curl -s "http://${ESHOST}:${ESPORT}/_cluster/health?wait_for_status=green&timeout=60s" >&/dev/null
        return_code=$?
        sleep 1
    done
    echo "Elasticsearch is up"
}

db_exists() {
	echo "Checking if database "${PGDBNAME}" exists..."
	count=`psql --host=${PGHOST} --port=${PGPORT} --user=${PGUSERNAME} --dbname=postgres -Atc "SELECT COUNT(*) FROM pg_catalog.pg_database WHERE datname='${PGDBNAME}'"`

	# Check if returned value is a number and not some error message
	re='^[0-9]+$'
	if ! [[ ${count} =~ $re ]] ; then
	   echo "Error: Something went wrong when checking if database "${PGDBNAME}" exists..." >&2;
	   echo "Exiting..."
	   exit 1
	fi

	# Return 0 (= true) if database exists
	if [[ ${count} > 0 ]]; then
		return 0
	else
		return 1
	fi
}

#### Install
init_arches() {
	echo "Checking if Arches project "${ARCHES_PROJECT}" exists..."
	if [[ ! -d ${APP_FOLDER} ]] || [[ ! "$(ls ${APP_FOLDER})" ]]; then
		echo ""
		echo "----- Custom Arches project '${ARCHES_PROJECT}' does not exist. -----"
		echo "----- Creating '${ARCHES_PROJECT}'... -----"
		echo ""

		cd ${WEB_ROOT}

		arches-project create ${ARCHES_PROJECT}
		run_setup_db

		exit_code=$?
		if [[ ${exit_code} != 0 ]]; then
			echo "Something went wrong when creating your Arches project: ${ARCHES_PROJECT}."
			echo "Exiting..."
			exit ${exit_code}
		fi
	else
		echo "Custom Arches project '${ARCHES_PROJECT}' exists."
		wait_for_db
		if db_exists; then
			echo "Database ${PGDBNAME} already exists."
			echo "Skipping Package Loading"
		else
			echo "Database ${PGDBNAME} does not exists yet."
			run_load_package #change to run_load_package if preferred 
		fi
	fi
}

# npm
# install_npm_components() {
# 	if [[ ! -d ${npm_MODULES_FOLDER} ]] || [[ ! "$(ls ${npm_MODULES_FOLDER})" ]]; then
# 		echo "npm modules do not exist, installing..."
# 		cd ${PACKAGE_JSON_FOLDER}
# 		npm install
# 	fi
# }

#### Misc
copy_settings_local() {
	# The settings_local.py in ${ARCHES_ROOT}/arches/ gets ignored if running manage.py from a custom Arches project instead of Arches core app
	echo "Copying ${APP_FOLDER}/docker/settings_docker.py to ${APP_FOLDER}/${ARCHES_PROJECT}/settings_docker.py..."
	cp ${APP_FOLDER}/docker/settings_docker.py ${APP_FOLDER}/${ARCHES_PROJECT}/settings_docker.py
	
	# Copy settings_local if it does not exist
	cp -n ${APP_FOLDER}/docker/settings_local.py ${APP_FOLDER}/${ARCHES_PROJECT}/settings_local.py
}

#### Run commands

start_celery_supervisor() {
	cd ${APP_FOLDER}
	supervisord -c docker/abac-permissions-demo-supervisor.conf
}

run_migrations() {
	echo ""
	echo "----- RUNNING DATABASE MIGRATIONS -----"
	echo ""
	cd ${APP_FOLDER}
	../ENV/bin/python manage.py migrate
}

run_setup_db() {
	echo ""
	echo "----- RUNNING SETUP_DB -----"
	echo ""
	cd ${APP_FOLDER}
	../ENV/bin/python manage.py setup_db --force
}

run_load_package() {
	echo ""
	echo "----- *** LOADING PACKAGE: ${ARCHES_PROJECT} *** -----"
	echo ""
	cd ${APP_FOLDER}
	../ENV/bin/python manage.py packages -o load_package -s abac_permissions_demo/pkg -db -dev -y
}

# "exec" means that it will finish building???
run_django_server() {
	echo ""
	echo "----- *** RUNNING DJANGO DEVELOPMENT SERVER *** -----"
	echo ""
	cd ${APP_FOLDER}
    echo "Running Django"
	exec /bin/bash -c "source ../ENV/bin/activate && pip3 install debugpy -t /tmp && python -Wdefault /tmp/debugpy --listen 0.0.0.0:5678 manage.py runserver 0.0.0.0:${DJANGO_PORT}"
}

#### Main commands
run_arches() {
	init_arches
	run_django_server
}

run_webpack() {
	echo ""
	echo "----- *** RUNNING WEBPACK DEVELOPMENT SERVER *** -----"
	echo ""
	cd ${APP_FOLDER}
    # echo "Running Webpack"
    #eval `ssh-agent -s` && cat /run/secrets/ssh_passphrase | SSH_ASKPASS=/bin/cat setsid -w ssh-add 2>> /dev/null
	exec /bin/bash -c "source ../ENV/bin/activate && cd /web_root/abac-permissions-demo && npm i && wait-for-it abac-permissions-demo:80 -t 1200 && npm start"
}
### Starting point ###

# Use -gt 1 to consume two arguments per pass in the loop
# (e.g. each argument has a corresponding value to go with it).
# Use -gt 0 to consume one or more arguments per pass in the loop
# (e.g. some arguments don't have a corresponding value to go with it, such as --help ).

# If no arguments are supplied, assume the server needs to be run
if [[ $#  -eq 0 ]]; then
	start_celery_supervisor
	wait_for_db
	run_arches
fi

# Else, process arguments
echo "Full command: $@"
while [[ $# -gt 0 ]]
do
	key="$1"
	echo "Command: ${key}"

	case ${key} in
		run_arches)
			start_celery_supervisor
			copy_settings_local
			wait_for_db
			run_arches
		;;
		setup_arches)
			start_celery_supervisor
			copy_settings_local
			wait_for_db
			setup_arches
		;;
		run_tests)
			copy_settings_local
			wait_for_db
			run_tests
		;;
		run_migrations)
			copy_settings_local
			wait_for_db
			run_migrations
		;;
		install_npm_components)
			install_npm_components
		;;
		help|-h)
			display_help
		;;
		*)
            cd ${APP_FOLDER}
			"$@"
			exit 0
		;;
	esac
	shift # next argument or value
done
