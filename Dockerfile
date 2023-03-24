# stage: 1
FROM node:16-alpine as react-build
WORKDIR /app
COPY ./sources/package.json /app
COPY ./sources/yarn.lock /app

# add dependencies for correct commands execution
RUN apk add git

RUN yarn
COPY ./sources/ /app

# Add git commit info to varible for showing
ARG REACT_APP_GIT_COMMIT_VERSION
ARG REACT_APP_GIT_BRANCH_NAME

RUN yarn build

# stage: 2 — the production environment
FROM nginx:alpine

# Nginx config
COPY ./sources/nginx.conf /etc/nginx/conf.d/default.conf

# Static build
COPY --from=react-build /app/build /usr/share/nginx/html
 
# Default port exposure
EXPOSE 80

# Copy .env file and shell script to container
WORKDIR /usr/share/nginx/html
COPY ./sources/env.sh .
COPY ./sources/.env .

RUN apk add bash

# Make our shell script executable
RUN chmod +x env.sh

# Start Nginx server
CMD ["/bin/bash", "-c", "/usr/share/nginx/html/env.sh && nginx -g \"daemon off;\""]
