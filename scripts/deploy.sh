#!/usr/bin/env bash
echo $BASH_VERSION
###########################
#### LOAD PARAMS
###########################
whitespace="[[:space:]]"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -h|--help)
      echo "\
      This script provides consistency in multiple deployments/upgrades on the Mine Digital Trust team's OCP4 namespaces 
      with options that effect: security, naming, themeing, environment, ledger 
      options can be provided as flags, or will be prompted in the execution

      Output is a helm upgrade --install command with --set <key from values.yaml>=<override_value> for each applicable value

      see 'helm_values_map' in this script to configure/see mapping from .yaml to script variables, can be added/updated as need
    
      FLAGS:
      -e, --environment, loads variables from /env/<parameter>.param file 
      -c, --config, loads variables from /config/<parameter>.param file 
      -d, --deployment, overrides helm deployment name (default=<config>) 
      -t, --title, sets the browser/tab title  
      -it, --image_tag, sets the image tag 
      --secret_file, loads any other variables from <parameter> file should refer to unversioned file for keycloak_client_secret

      SIMPLE EXAMPLE: 
      ./deploy.sh -c demo -e dev
      
      COMPLEX EXAMPLE: 
      ./deploy.sh -c demo -e dev -d my-example -t 'My Example'

      KEYCLOAK EXAMPLE: 
      ./deploy.sh -c gov -e dev --secret_file example_secret_file -d dev_gov_keycloak
       " 
      exit 1
      ;;
    -e|--environment)
      ENVIRONMENT="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--config)
      CONFIG="$2"
      shift # past argument
      shift # past value
      ;;
    -d|--deployment_name)
      DEPLOYMENT_NAME_OVERRIDE="$2"
      shift # past argument
      shift # past value
      ;;
    -t|--title)
      if [[ $2 =~ $whitespace ]]
      then
        TITLE_OVERRIDE=\"$2\"
      else
        TITLE_OVERRIDE=$2
      fi
      shift # past argument
      shift # past value
      ;;
    -it|--image_tag)
      IMAGE_TAG_OVERRIDE="$2"
      shift # past argument
      shift # past value
      ;;
    --secret-file)
      SECRET_FILE="$2"
      shift # past argument
      shift # past value
      ;;
    *)    # unknown option
      POSITIONAL+=("$1") # save it in an array for later
      shift # past argument
      ;;
  esac
done

###########################
#### LOAD PROFILES
###########################

## --secret-file for things that shouldn't be source controlled
if [ $SECRET_FILE ]
then
    source $SECRET_FILE
fi

if  [ $ENVIRONMENT ]
then 
    echo "-e flag provided, loading environment profile"
else
    read -p "-e not set: provide environment name (dev, test, prod): " ENVIRONMENT
fi
if [ $ENVIRONMENT ]
then
    eval "oc project f6b17d-${ENVIRONMENT}"
    source ./env/$ENVIRONMENT.param
else 
    echo "not set, using defaults (../charts/bpa/values.yaml)"
fi

if [ $CONFIG ]
then 
    echo "-c flag provided, loading config profile"
else
    read -p "-c not set: provide config name (see config folder): " CONFIG
fi    
if [ $CONFIG ]
then
    source ./config/$CONFIG.param
else 
    echo "not set, using defaults (../charts/bpa/values.yaml)"
fi


###########################
#### SET VARIABLES
###########################
declare -A helm_values_map

## config
declare BPA_VAR_NAME=${ENVIRONMENT^^}_DEPLOYMENT_NAME
declare BPA_VAR_TITLE=${ENVIRONMENT^^}_DEPLOYMENT_TITLE
declare BPA_TITLE_OVERRIDE=${TITLE_OVERRIDE:-\"${!BPA_VAR_TITLE}\"}
helm_values_map["bpa.config.nameOverride"]="${!BPA_VAR_NAME}"
helm_values_map["bpa.config.titleOverride"]=\"$BPA_TITLE_OVERRIDE\"
helm_values_map["bpa.config.i18n.locale"]=$BPA_I18N_LOCALE
helm_values_map["ux.preset"]=$UX_PRESET
helm_values_map["ux.config.theme.themes.light.primary"]=$UX_PRIMARY_COLOR
helm_values_map["ux.config.theme.themes.light.icons"]=$UX_ICONS_COLOR

## image
declare BPA_IMAGE_TAG_OVERRIDE=${IMAGE_TAG_OVERRIDE:-${IMAGE_TAG}}
helm_values_map["bpa.image.tag"]=${BPA_IMAGE_TAG_OVERRIDE}
helm_values_map["bpa.image.repository"]=$BPA_IMAGE_REPO

## environment
## loaded from .env config, then can be overriden in .param config
helm_values_map["global.ingressSuffix"]=$INGRESS_SUFFIX

## ledger
helm_values_map["bpa.ledger.browserUrlOverride"]=$BPA_LEDGER_BROWSER_URL
helm_values_map["bpa.ledger.genesisUrlOverride"]=$BPA_LEDGER_GENESIS_URL

helm_values_map["schemas.enabled"]=$SCHEMAS_ENABLED
helm_values_map["schemas.minesActPermit.enabled"]=$SCHEMAS_MINESACT_ENABLED
helm_values_map["schemas.emissionsProfile.enabled"]=$SCHEMAS_EMISSIONS_ENABLED
helm_values_map["schemas.tsm.enabled"]=$SCHEMAS_TSM_ENABLED

## security
helm_values_map["bpa.config.security.enabled"]=$BPA_SECURITY_ENABLED
helm_values_map["keycloak.enabled"]=$BPA_KEYCLOAK_ENABLED

## security.keycloak
helm_values_map["keycloak.clientId"]=$KEYCLOAK_CLIENT_ID
helm_values_map["keycloak.config.issuer"]=$KEYCLOAK_ISSUER_URL
helm_values_map["keycloak.config.endsessionUrl"]=$KEYCLOAK_END_SESSION_URL
helm_values_map["keycloak.config.vcauthn_pres_req_conf_id"]=$KEYCLOAK_CONFIG_VCAUTHN_PRES_REQ_CONF_ID

## nav-header custom
helm_values_map["ux.config.favicon.href"]=$UX_FAVICON_HREF
helm_values_map["ux.config.navigation.avatar.agent.enabled"]=$UX_NAVIGATION_AVATAR_AGENT_ENABLED
helm_values_map["ux.config.navigation.avatar.agent.default"]=$UX_NAVIGATION_AVATAR_AGENT_DEFAULT
helm_values_map["ux.config.navigation.avatar.agent.src"]=$UX_NAVIGATION_AVATAR_AGENT_SRC
helm_values_map["ux.config.navigation.avatar.agent.showName"]=$UX_NAVIGATION_AVATAR_AGENT_SHOW_NAME
helm_values_map["ux.config.navigation.about.enabled"]=$UX_NAVIGATION_ABOUT_ENABLED
helm_values_map["ux.config.navigation.logout.enabled"]=$UX_NAVIGATION_LOGOUT_ENABLED
helm_values_map["ux.config.navigation.settings.location"]=$UX_NAVIGATION_SETTINGS_LOCATION
helm_values_map["ux.config.header.logout.enabled"]=$UX_HEADER_LOGOUT_ENABLED


if $BPA_KEYCLOAK_ENABLED && [ -z $KEYCLOAK_CLIENT_SECRET ]
then
    read -p "Keycloak enabled, provide client secret for (env=$ENVIRONMENT, client_id=$KEYCLOAK_CLIENT_ID): " KEYCLOAK_CLIENT_SECRET
    if [ -z $KEYCLOAK_CLIENT_SECRET ]
    then 
        echo "don't skip that next time"
        exit 1
    fi
fi
helm_values_map["keycloak.clientSecret"]=$KEYCLOAK_CLIENT_SECRET


if $BPA_SECURITY_ENABLED && [[ $BPA_BOOTSTRAP_OVERRIDE ]] && [ $BPA_BOOTSTRAP_OVERRIDE ]
then
    echo "Local security enabled, overriding bootstrap defaults."
    if [ -z $BPA_BOOTSTRAP_USERNAME ]
    then
        read -p "Provide bootstrap username: " BPA_BOOTSTRAP_USERNAME
        if [ -z $BPA_BOOTSTRAP_USERNAME ]
        then 
            echo "don't skip that next time"
            exit 1
        fi
    fi

    if [ -z $BPA_BOOTSTRAP_PASSWORD ]
    then
        read -p "Provide password for $BPA_BOOTSTRAP_USERNAME: " BPA_BOOTSTRAP_PASSWORD
        if [ -z $BPA_BOOTSTRAP_PASSWORD ]
        then 
            echo "don't skip that next time"
            exit 1
        fi
    fi
helm_values_map["bpa.config.bootstrap.username"]=$BPA_BOOTSTRAP_USERNAME
helm_values_map["bpa.config.bootstrap.password"]=$BPA_BOOTSTRAP_PASSWORD
fi

###########################
#### Construct Command
###########################

declare DEPLOYMENT_NAME=${DEPLOYMENT_NAME_OVERRIDE:-$CONFIG$DEPLOYMENT_SUFFIX}


CMD="helm upgrade $DEPLOYMENT_NAME ../charts/bpa -f ../charts/bpa/values.yaml --install"
SET_PARAMS=

for key in "${!helm_values_map[@]}"; do
    [ -z "${helm_values_map[$key]}" ] || SET_PARAMS="$SET_PARAMS --set $key=\"${helm_values_map[$key]}\""
done


eval "${CMD} ${SET_PARAMS}"

###########################
#### FORCE REDEPLOY
###########################

# pod_name="oc get pods --no-headers | grep $CONFIG-bpa-core"
# eval "oc delete pod $pod_name"


###########################
#### TAG IMAGE
###########################

# oc -n f6b17d-tools tag bcgov-b2b:latest bcgov-b2b:test