FROM public.ecr.aws/l1p7h1f9/archesproject-fargeo:7.6.x-base-dev

ARG ARCHES_CORE_HOST_DIR

## Setting default environment variables
ENV WEB_ROOT=/web_root
ENV APP_ROOT=${WEB_ROOT}/abac-permissions-demo
# Root project folder
ENV ARCHES_ROOT=${WEB_ROOT}/arches

WORKDIR ${WEB_ROOT}

# Install the Arches application
# FIXME: ADD from github repository instead?
COPY ${ARCHES_CORE_HOST_DIR} ${ARCHES_ROOT}
COPY ../arches-synthetic-data ${WEB_ROOT}/arches-synthetic-data
COPY ../arches-rule-based-permissions-poc ${WEB_ROOT}/arches-rule-based-permissions-poc
COPY ./abac-permissions-demo ${APP_ROOT}

WORKDIR ${APP_ROOT}
RUN source ../ENV/bin/activate && pip install -e '.[dev]' && pip uninstall arches -y
RUN source ../ENV/bin/activate && cd ${WEB_ROOT}/arches-rule-based-permissions-poc && pip install -e . && pip install -e '.[dev]' --no-binary :all:
RUN source ../ENV/bin/activate && cd ${WEB_ROOT}/arches-synthetic-data && pip install -e . && pip install -e '.[dev]' --no-binary :all:
WORKDIR ${ARCHES_ROOT}
RUN source ../ENV/bin/activate && pip install -e . && pip install -e '.[dev]' --no-binary :all:

# TODO: These are required for non-dev installs, currently only depends on arches/afs
#RUN pip install -r requirements.txt

COPY /abac-permissions-demo/docker/entrypoint.sh ${WEB_ROOT}/entrypoint.sh
RUN chmod -R 700 ${WEB_ROOT}/entrypoint.sh &&\
  dos2unix ${WEB_ROOT}/entrypoint.sh

# Set default workdir
WORKDIR ${APP_ROOT}

# # Set entrypoint
ENTRYPOINT ["../entrypoint.sh"]
CMD ["run_arches"]

# Expose port 8000
EXPOSE 8000
