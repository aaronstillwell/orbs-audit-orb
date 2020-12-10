Audit() {
    # Globals passed from parameters
    CONFIG_FILE_LOCATION=$CONFIG_FILE_LOCATION
    FAIL_ON_UNPINNED=$FAIL_ON_UNPINNED

    # Color related vars
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'

    # Exit code to be returned at the end
    STATUS=0

    # Helper functions for printing colored text to stdout

    print_green() {
        echo -e "${GREEN}${1}${NC}"
    }

    print_yellow() {
        echo -e "${YELLOW}${1}${NC}"
    }

    print_red() {
        echo -e "${RED}${1}${NC}"
    }

    # Print a problem in either red or yellow, depending on how the command is
    # configured
    print_problem() {
        print_red "${1}"
    }

    # $1 -> fully qualified orb ref
    # $2 -> type
    # $3 -> message
    # $4 -> assertions
    generate_failed_xml() {
        echo "<testcase name=\"${1}\" file=\"${CONFIG_FILE_LOCATION}\" assertions='${4}'><failure type=\"${2}\" message=\"${2}\"></failure></testcase>"
    }

    #
    generate_error_xml() {
        echo "<testcase name=\"${1}\" file=\"${CONFIG_FILE_LOCATION}\" assertions='${4}'><error type=\"${2}\">${3}</error></testcase>"
    }

    # $1 -> fully qualified orb ref
    generate_passed_xml() {
        echo "<testcase name=\"${1}\" file=\"${CONFIG_FILE_LOCATION}\" assertions='${2}'></testcase>"
    }

    # TODO fail if file is not present

    XML=""
    ERROR_COUNT=0
    FAIL_COUNT=0
    SKIPPED_COUNT=0
    TESTS_COUNT=0
    ASSERTION_COUNT=0

    ORBS=$(cat ${CONFIG_FILE_LOCATION} | yq r - "orbs.*")
    while IFS= read -r orb; do
        ORB_REGEX="^([A-z_-]+)\/([A-z_-]+)(@([0-9]+)(\.([0-9]+))?(\.([0-9]+))?)?$"

        if ! [[ $orb =~ $ORB_REGEX ]]; then
        # Skip inline orbs, orbs using parameters
        continue
        fi

        TESTS_COUNT=$((TESTS_COUNT+1))
        ASSERTION_COUNT=$((ASSERTION_COUNT+1))

        META=$(circleci --skip-update-check orb info $orb)
        REGEX="Latest: [A-z-]+\/[A-z-]+@([0-9]+)\.([0-9]+)\.([0-9]+)"

        if [[ $META =~ $REGEX ]]; then
        LATEST_MAJOR=${BASH_REMATCH[1]}
        LATEST_MINOR=${BASH_REMATCH[2]}
        LATEST_PATCH=${BASH_REMATCH[3]}

        ASSERTION_COUNT=$((ASSERTION_COUNT+1))
        # Don't think ERE supports non-capture groups
        CURRENT_REGEX="@([0-9]+)(\.([0-9]+))?(\.([0-9]+))?"
        if [[ $orb =~ $CURRENT_REGEX ]]; then

            CURRENT_MAJOR=${BASH_REMATCH[1]}
            CURRENT_MINOR=${BASH_REMATCH[3]}
            CURRENT_PATCH=${BASH_REMATCH[5]}

            # TODO: support less specific orb pinning

            ASSERTION_COUNT=$((ASSERTION_COUNT+1))
            if [ "$CURRENT_MAJOR" != "" ]; then
            if [ $CURRENT_MAJOR -ne $LATEST_MAJOR ]; then
                # New major version available
                print_problem "New major version of ${orb} available"
                XML+=$(generate_failed_xml ${orb} "New major version available" "A new major version of this orb is available" 3)
                FAIL_COUNT=$((FAIL_COUNT+1))
                STATUS=1
                continue
            fi
            fi

            ASSERTION_COUNT=$((ASSERTION_COUNT+1))
            if [ "$CURRENT_MINOR" != "" ]; then
            if [ $CURRENT_MINOR -ne $LATEST_MINOR ]; then
                # New major minor available
                print_problem "New minor version of $orb available"
                XML+=$(generate_failed_xml ${orb} "New minor version available" "A new minor version of this orb is available" 4)
                FAIL_COUNT=$((FAIL_COUNT+1))
                STATUS=1
                continue
            fi
            fi

            ASSERTION_COUNT=$((ASSERTION_COUNT+1))
            if [ "$CURRENT_PATCH" != "" ]; then
            if [ $CURRENT_PATCH -ne $LATEST_PATCH ]; then
                # New patch version available
                print_problem "New patch version of $orb available"
                XML+=$(generate_failed_xml ${orb} "New minor version available" "A new patch sversion of this orb is available" 5)
                FAIL_COUNT=$((FAIL_COUNT+1))
                STATUS=1
                continue
            fi
            fi

            print_green "${orb} is up to date"
            XML+="$(generate_passed_xml ${orb} 5)"
        else
            print_red "Couldn't identify pinned version of $orb"
            XML+=$(generate_error_xml ${orb} "Could not identify pinned version" "Could not identify the pinned version of ${orb}" 2)
            FAIL_COUNT=$((FAIL_COUNT+1))
            if $FAIL_ON_UNPINNED ; then
            STATUS=1
            fi
        fi
        else
        print_red "Could not find orb info for $orb"
        ERROR_COUNT=$((ERROR_COUNT+1))
        XML+=$(generate_error_xml ${orb} "Orb not found" "Could not find orb ${orb} in the registry" 1)
        STATUS=1
        fi
    done <<< "${ORBS}"

    TIMESTAMP=`date +%Y-%m-%dT%H:%M:%S%:z`
    XML=$(printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuite skipped='${SKIPPED_COUNT}' assertions='${ASSERTION_COUNT}' errors='${ERROR_COUNT}' failures='${FAIL_COUNT}' tests='${TESTS_COUNT}' name=\"Outdated orbs helper\" timestamp=\"${TIMESTAMP}\">\n${XML}\n")
    XML+="</testsuite>"

    mkdir -p ".outdated-orbs-helper"

    echo "${XML}" > ".outdated-orbs-helper/results.xml"

    exit $STATUS
}

# Will not run if sourced for bats-core tests.
# View src/tests for more information.
ORB_TEST_ENV="bats-core"
if [ "${0#*$ORB_TEST_ENV}" == "$0" ]; then
    Audit
fi
