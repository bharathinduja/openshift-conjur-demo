#!/bin/bash
set -eou pipefail

. ./openshift-conjur-deploy/utils.sh
. ./utils.sh

set_project $CONJUR_PROJECT_NAME

conjur_master=$(get_master_pod_name)

# (re)install Conjur policy plugin
oc exec $conjur_master -- touch /opt/conjur/etc/plugins.yml
oc exec $conjur_master -- conjur plugin uninstall policy
oc exec $conjur_master -- conjur plugin install policy

pushd policy
  sed -e "s#{{ TEST_APP_PROJECT_NAME }}#$TEST_APP_PROJECT_NAME#g" ./authn-k8s.template.yml > ./authn-k8s.yml
popd

oc rsync ./policy $conjur_master:/

oc exec $conjur_master -- conjur authn login -u admin -p $CONJUR_ADMIN_PASSWORD
oc exec $conjur_master -- conjur policy load --as-group security_admin "policy/conjur.yml"

oc exec $conjur_master -- rm -rf ./policy

password=$(openssl rand -hex 12)

echo "Setting DB password: $password"
oc exec $conjur_master -- conjur variable values add test-app-db/password $password

oc exec $conjur_master -- conjur-plugin-service authn-k8s rake ca:initialize["conjur/authn-k8s/openshift-test"]
