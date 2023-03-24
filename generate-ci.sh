#!/usr/bin/env bash 

cd ..
mkdir -p ./temp
cd ./temp
echo "$DEPLOYKEY" > ./deploykey
if [ $(echo ${CI_COMMIT_AUTHOR} | wc -w ) == 3 ]; then COMMIT_AUTHOR_NAME=$(echo ${CI_COMMIT_AUTHOR} | awk -F' ' '{print $1, $2}'); else COMMIT_AUTHOR_NAME=$(echo ${CI_COMMIT_AUTHOR} | awk -F' ' '{print $1}'); fi;
COMMIT_AUTHOR_EMAIL=$(echo ${CI_COMMIT_AUTHOR} | awk -F' ' '{print $NF}' | sed -e "s/[<,>]//g")
git config --global url."git@git.xxxxxxxxxxxxx.ru:".insteadOf "https://git.xxxxxxxxxxxxx.ru/"
git config --global user.email "${COMMIT_AUTHOR_EMAIL}"
git config --global user.name "${COMMIT_AUTHOR_NAME}"
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keyscan -H git.xxxxxxxxxxxxx.ru >> ~/.ssh/known_hosts
chmod 400 ./deploykey
eval $(ssh-agent -s)
ssh-add ./deploykey
git clone git@git.xxxxxxxxxxxxx.ru:magicairpro/deploy-yc-compose/deploy-kontur.git
cd deploy-kontur      
cat CI/gitlab-ci.yml.tpl > .gitlab-ci.yml
declare -a ListOfKontours=($(cat CI/list-of-konturs.txt))
for val in ${ListOfKontours[@]}; do
echo "" >>  .gitlab-ci.yml
cat  << EOF >> .gitlab-ci.yml
deploy_environment_${val}:
  stage: deploy
  extends: .environment_template
  only:
    refs:
      - web
      - pipelines
    variables:
      - \$TARGET_KONTUR == "${val}"
      - \$TARGET_KONTUR == "all"
      - \$TARGET_KONTUR =~ /${val}/
  before_script: 
    - export TARGET_KONTUR_VAL=${val}
  artifacts:
    reports:
      dotenv: deploy-${val}.env
  environment:
    name: ${val}
    url: https://\${DOMAIN}
EOF
done
git add .
git commit -m "generate .gitlab-ci.yml file"
git push origin main -o skip-ci
cd ../..
rm -rf ./temp
