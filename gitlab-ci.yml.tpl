stages:
  - generate-ci
  - release
  - build
  - backup-db
  - deploy

default:
  tags:
    - yc-shell
  before_script:
    - |
       if [[ $TARGET_KONTUR == "" ]]; then TARGET_KONTUR="develop"; fi
       if [[ $TARGET_KONTUR == "all" ]]; then TARGET_KONTUR=($(cat CI/list-of-konturs.txt)); fi
       if [[ $FRONT_BRANCH == "" ]]; then FRONT_BRANCH="develop"; fi
       if [[ $BACK_BRANCH == "" ]]; then BACK_BRANCH="develop"; fi
       if [[ $DOCKER_TAG_VERSION == "" ]]; then DOCKER_TAG_VERSION="dev"; fi
       FRONTEND_TAG=$DOCKER_TAG_VERSION
       BACKEND_TAG=$DOCKER_TAG_VERSION
       if [[ $DOCKER_TAG_VERSION == "v2" ]]; then BACKEND_TAG="dev"; fi
       export TARGET_KONTUR FRONT_BRANCH BACK_BRANCH DOCKER_TAG_VERSION FRONTEND_TAG BACKEND_TAG

variables:
  IS_RELEASE:
    value: "no"
    description: "If you want to deploy a release, specify the name of the release tag."
  NEED_BUILD_IMAGES: 
    value: "no"
    description: "'yes' to build images from branches, 'no' to deploy exist images from yandex.registry."
  DOCKER_TAG_VERSION:
    value: "dev"
    description: "You must specify Docker image Tag: 'dev', 'qa', 'prod', 'vX.X.X' etc."
  FRONT_BRANCH:
    value: "develop"
    description: "You must specify frontend branch name to build image: 'develop', 'qa', 'demo', 'master' etc."
  BACK_BRANCH:
    value: "develop"
    description: "You must specify backend branch name to build image: 'develop', 'qa', 'demo', 'master' etc."
  BACKUP_DATABASE:
    value: "no"
    description: "'yes' to make backups databases before deploy, 'no' deploy without backups"
  TARGET_KONTUR:
    value: "develop"
    description: "You must specify target kontur: develop qa experiments demo-generic demo-tion demo-sok demo-cushwake demo-cityair demo-sales demo-gornostay demo-uzmolkom demo-hals demo-rosneft demo-f2"
  FRONT_IMAGE: "${YANDEX_REGISTRY}/map/frontend"
  AUTH_SRV: "${YANDEX_REGISTRY}/map/authorization"
  MAP_SRV: "${YANDEX_REGISTRY}/map/magicairpro"
  SENSORS_SRV: "${YANDEX_REGISTRY}/map/sensorvalues"
  ADAPTER_SRV: "${YANDEX_REGISTRY}/map/magicairadapter"
  
generate_ci_job:
  stage: generate-ci
  only:
    refs:
      - main
    changes:
      - CI/gitlab-ci.yml.tpl
      - CI/list-of-konturs.txt
      - CI/generate-ci.sh
  except:
    refs:
      - pipelines
      - web
  script:
    - CI/generate-ci.sh
  
release_job:
  stage: release
  only:
    refs:
      - tags
  except:
    refs:
      - pipelines
      - web
  script:
    - source Release/version
    - |
      echo "**FRONTEND**  " >> RELEASE_DESCRIPTION
      echo -e $(release-cli --server-url https://git.tiondev.ru --project-id 46 --private-token "${API_READ_ACCESS_TOKEN}" get --tag-name "${FRONTEND}" 2>/dev/null | jq '.description' | sed -e "s/\"//g")"  " >> RELEASE_DESCRIPTION
      echo "  " >> RELEASE_DESCRIPTION
      echo "**BACKEND**  " >> RELEASE_DESCRIPTION
      echo -e $(release-cli --server-url https://git.tiondev.ru --project-id 47 --private-token "${API_READ_ACCESS_TOKEN}" get --tag-name "${BACKEND}" 2>/dev/null | jq '.description' | sed -e "s/\"//g")"  " >> RELEASE_DESCRIPTION
    - release-cli create --name "MagicAir.PRO Release ${CI_COMMIT_TAG}" --description RELEASE_DESCRIPTION --tag-name "${CI_COMMIT_TAG}" --assets-link "{\"name\":\"Frontend ${FRONTEND}\",\"url\":\"https://git.tiondev.ru/magicairpro/frontend/tion.magicairpro.frontend/-/releases/${FRONTEND}\",\"link_type\":\"other\"}" --assets-link "{\"name\":\"Backend ${BACKEND}\",\"url\":\"https://git.tiondev.ru/magicairpro/backend/mapservices/-/releases/${BACKEND}\",\"link_type\":\"other\"}"

build_frontend_image:
  stage: build
  only:
    refs:
      - web
    variables:
      - $IS_RELEASE == "no" && $NEED_BUILD_IMAGES == "yes"
  variables:
    DOCKER_TAG_VERSION: ${DOCKER_TAG_VERSION}
  trigger:
    project: magicairpro/frontend/tion.magicairpro.frontend
    branch: ${FRONT_BRANCH}
    strategy: depend

build_backend_image:
  stage: build
  only:
    refs:
      - web
    variables:
      - $IS_RELEASE == "no" && $NEED_BUILD_IMAGES == "yes"
  variables:
    DOCKER_TAG_VERSION: ${DOCKER_TAG_VERSION}
  trigger:
    project: magicairpro/backend/mapservices
    branch: ${BACK_BRANCH}
    strategy: depend

backup_databases:
  stage: backup-db
  only:
    refs:
      - web
    variables:
      - $BACKUP_DATABASE == "yes"
  script: 
    - |
      export VAULT_SKIP_VERIFY=true
      export VAULT_ADDR=http://vault.service.yc.map:8200
      for val in ${TARGET_KONTUR[@]}; do
        ssh -o LogLevel=QUIET -tt ubuntu@master-a -i ~/.ssh/id_ed25519 "sudo mkdir -p /mnt/vdb1/backup/${val}; sudo chmod 0777 /mnt/vdb1/backup/${val}; exit 0"
        export VAULT_TOKEN="$(vault write -field=token auth/jwt/login role=deploy-kontur jwt=$CI_JOB_JWT)"
        database_auth="$(vault kv get -field=database_auth secrets/map/kontur/${val}/terraform)"
        database_data="$(vault kv get -field=database_data secrets/map/kontur/${val}/terraform)"
        database_serv="$(vault kv get -field=database_serv secrets/map/kontur/${val}/terraform)"
        pgusername="$(vault kv get -field=dbuser secrets/map/kontur/${val}/terraform)"
        pgpassword="$(vault kv get -field=dbpass secrets/map/kontur/${val}/terraform)"
        pghost="$(vault kv get -field=dbhost secrets/map/kontur/${val}/terraform)"
        pgport="$(vault kv get -field=dbport secrets/map/kontur/${val}/terraform)"
        PGPASSWORD="${pgpassword}" pg_dump --username=${pgusername} --dbname=postgresql://${pghost}:${pgport}/${database_auth} | gzip > "/home/gitlab-runner/backup-db/${val}/${database_auth}-$(date +%Y-%m-%d-%H-%M).psql.gz"
        PGPASSWORD="${pgpassword}" pg_dump --username=${pgusername} --dbname=postgresql://${pghost}:${pgport}/${database_data} | gzip > "/home/gitlab-runner/backup-db/${val}/${database_data}-$(date +%Y-%m-%d-%H-%M).psql.gz"
        PGPASSWORD="${pgpassword}" pg_dump --username=${pgusername} --dbname=postgresql://${pghost}:${pgport}/${database_serv} | gzip > "/home/gitlab-runner/backup-db/${val}/${database_serv}-$(date +%Y-%m-%d-%H-%M).psql.gz"
      done

deploy_nomad:
  stage: deploy
  only:
    refs:
      - web
      - pipelines
  script: 
    - |
      if [[ $IS_RELEASE != "no" ]] 
      then
        git checkout $IS_RELEASE
        source Release/version
        export BACKEND_TAG=$BACKEND
        export FRONTEND_TAG=$FRONTEND
      fi
    - |
      export VAULT_SKIP_VERIFY=true
      export VAULT_ADDR=http://vault.service.yc.map:8200
      for val in ${TARGET_KONTUR[@]}; do
        export KONTUR_TEMPLATE=${val}
        export VAULT_TOKEN="$(vault write -field=token auth/jwt/login role=deploy-kontur jwt=$CI_JOB_JWT)"
        rabbitmq_mem_max=$(($(vault kv get -field=mqttbroker_memory secrets/map/kontur/${val}/nomad)*943000))
        consul-template -template "config-kontur/magicairpro-job.hcl.tpl:config-kontur/magicairpro-job.hcl" -once -vault-renew-token=false
        export NOMAD_JOB="config-kontur/magicairpro-job.hcl"
        ssh -o LogLevel=QUIET -tt ubuntu@master-a -i ~/.ssh/id_ed25519 "sudo mkdir -p /mnt/vdb1/rmq/${val}; sudo chmod 0777 /mnt/vdb1/rmq/${val}; sudo chown systemd-coredump:nogroup /mnt/vdb1/rmq/${val}; exit 0"
        nomad namespace apply -description "${val} Kontur" ${val}
        nomad plan --var="version=${CI_JOB_ID}" \
                --var="sensor_image=${SENSORS_SRV}:${BACKEND_TAG}" \
                --var="auth_image=${AUTH_SRV}:${BACKEND_TAG}" \
                --var="map_image=${MAP_SRV}:${BACKEND_TAG}" \
                --var="front_image=${FRONT_IMAGE}:${FRONTEND_TAG}" \
                --var="kontur=${val}" "${NOMAD_JOB}" || if [ $? -eq 255 ]; then exit 255; else echo "success"; fi
        nomad run --var="version=${CI_JOB_ID}" \
                --var="sensor_image=${SENSORS_SRV}:${BACKEND_TAG}" \
                --var="auth_image=${AUTH_SRV}:${BACKEND_TAG}" \
                --var="map_image=${MAP_SRV}:${BACKEND_TAG}" \
                --var="front_image=${FRONT_IMAGE}:${FRONTEND_TAG}" \
                --var="kontur=${val}" "${NOMAD_JOB}"
        nomad alloc exec -namespace=${val} -task rabbitmq \
                $(nomad job status -namespace=${val} magicairpro | grep 'map' | grep 'running' | awk -F' ' '{print $1}') \
                rabbitmqctl set_vm_memory_high_watermark absolute $rabbitmq_mem_max || echo ""
      done

.environment_template:
  stage: deploy
  needs:
    - deploy_nomad
  script: 
    - |
      git pull -q -r ${CI_REPOSITORY_URL}
      if [[ $TARGET_KONTUR == "" ]]; then TARGET_KONTUR="develop"; fi
      if [[ $TARGET_KONTUR == "all" ]]; then TARGET_KONTUR=($(cat CI/list-of-konturs.txt)); fi
      if [[ $FRONT_BRANCH == "" ]]; then FRONT_BRANCH="develop"; fi
      if [[ $BACK_BRANCH == "" ]]; then BACK_BRANCH="develop"; fi
      if [[ $DOCKER_TAG_VERSION == "" ]]; then DOCKER_TAG_VERSION="dev"; fi
      FRONTEND_TAG=$DOCKER_TAG_VERSION
      BACKEND_TAG=$DOCKER_TAG_VERSION
      if [[ $DOCKER_TAG_VERSION == "v2" ]]; then BACKEND_TAG="dev"; fi
      export TARGET_KONTUR FRONT_BRANCH BACK_BRANCH DOCKER_TAG_VERSION FRONTEND_TAG BACKEND_TAG
      echo "        "
      date
      export VAULT_SKIP_VERIFY=true
      export VAULT_ADDR=http://vault.service.yc.map:8200
      export VAULT_TOKEN="$(vault write -field=token auth/jwt/login role=deploy-kontur jwt=$CI_JOB_JWT)"
      export DOMAIN="$(vault kv get -field=KONTUR_DOMAIN secrets/map/kontur/${TARGET_KONTUR_VAL}/common)"
      echo "DOMAIN=$DOMAIN" >> deploy-${TARGET_KONTUR_VAL}.env
      if [[ $IS_RELEASE != "no" ]] 
      then
      sleep $((3 + $RANDOM % 10))
      git checkout $IS_RELEASE
      source Release/version
      git checkout main
      export RELEASE_FOR_OUTPUT="MagicAir.PRO RELEASE ${IS_RELEASE}"
      cat << EOF
      ------------------------------------------------------------------------------------------------------
          Deploying ${RELEASE_FOR_OUTPUT} to environment and KONTUR: '${TARGET_KONTUR_VAL}'
          https://git.tiondev.ru/magicairpro/deploy-yc-compose/deploy-kontur/-/releases/${IS_RELEASE}
      ------------------------------------------------------------------------------------------------------
          
          FRONTEND RELEASE: ${FRONTEND}
          https://git.tiondev.ru/magicairpro/frontend/tion.magicairpro.frontend/-/releases/${FRONTEND}
      ------------------------------------------------------------------------------------------------------
          
          BACKEND RELEASE: ${BACKEND}
          https://git.tiondev.ru/magicairpro/backend/mapservices/-/releases/${BACKEND}
      ------------------------------------------------------------------------------------------------------

          Docker images:
              ${AUTH_SRV}:${BACKEND}
              ${MAP_SRV}:${BACKEND}
              ${SENSORS_SRV}:${BACKEND}
              ${FRONT_IMAGE}:${FRONTEND}
      ------------------------------------------------------------------------------------------------------             
          Kontur url: https://${DOMAIN} 
                                        
      EOF
      else
      FRONTIMG=$(echo "FRONTEND  "; cat ./logs/dockerimg/frontend-${FRONTEND_TAG}.log 2>/dev/null || if [ $? -eq 1 ]; then echo "not found"; fi )
      AUTHIMG=$(echo "AUTHORIZATION  "; cat ./logs/dockerimg/authorization-${BACKEND_TAG}.log 2>/dev/null || if [ $? -eq 1 ]; then echo "not found"; fi )
      PROIMG=$(echo "MAGICAIRPRO  "; cat ./logs/dockerimg/magicairpro-${BACKEND_TAG}.log 2>/dev/null || if [ $? -eq 1 ]; then echo "not found"; fi )
      SENSORIMG=$(echo "SENSORVALUES  "; cat ./logs/dockerimg/sensorvalues-${BACKEND_TAG}.log 2>/dev/null || if [ $? -eq 1 ]; then echo "not found"; fi )
      cat << EOF
      ------------------------------------------------------------------------------------------------------
          Deploying to environment and KONTUR: '${TARGET_KONTUR_VAL}'
      ------------------------------------------------------------------------------------------------------
          
          FRONTEND BRANCH: ${FRONT_BRANCH}
      ------------------------------------------------------------------------------------------------------

          ${FRONTIMG}
      ------------------------------------------------------------------------------------------------------
            
          BACKEND BRANCH:  ${BACK_BRANCH}
      ------------------------------------------------------------------------------------------------------

          ${AUTHIMG}
      ------------------------------------------------------------------------------------------------------

          ${PROIMG}
      ------------------------------------------------------------------------------------------------------

          ${SENSORIMG}
      ------------------------------------------------------------------------------------------------------
            
          Docker images:
            ${AUTH_SRV}:${BACKEND_TAG}
            ${MAP_SRV}:${BACKEND_TAG}
            ${SENSORS_SRV}:${BACKEND_TAG}
            ${FRONT_IMAGE}:${FRONTEND_TAG}
      ------------------------------------------------------------------------------------------------------             
          Kontur url: https://${DOMAIN} 
                                        
      EOF
      fi
