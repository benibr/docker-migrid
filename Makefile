PACKAGE_NAME=docker-migrid
PACKAGE_NAME_FORMATTED=$(subst -,_,$(PACKAGE_NAME))
IMAGE=migrid
OWNER ?= ucphhpc
SHELL=/bin/bash

# Enable that the builder should use buildkit
# https://docs.docker.com/develop/develop-images/build_enhancements/
DOCKER_BUILDKIT=1
# NOTE: dynamic lookup with docker as default and fallback to podman
DOCKER = $(shell which docker || which podman)
# if compose is not found, try to use it as plugin, eg. RHEL8
DOCKER_COMPOSE = $(shell which docker-compose || which podman-compose || echo 'docker compose')
$(echo ${DOCKER_COMPOSE} >/dev/null)

.PHONY: all init clean warning
.PHONY: dockerclean distclean stateclean dockerbuild dockerpush
.PHONY: up stop down
.PHONY: test-doc

.ONESHELL:

ifeq ("$(wildcard .env)",".env")
include .env
endif

all: init dockerbuild up

init:
ifeq (,$(wildcard ./Dockerfile))
	@echo
	@echo "*** No Dockerfile selected - defaulting to centos7 ***"
	@echo
	ln -s Dockerfile.centos7 Dockerfile
	@sleep 2
endif
ifeq (,$(wildcard ./.env))
	@echo
	@echo "*** No deployment environment selected - defaulting to development ***"
	@echo
	ln -s development.env .env
	@sleep 2
endif
ifeq (,$(wildcard ./docker-compose.yml))
	@echo
	@echo "*** No docker-compose.yml selected - defaulting to development ***"
	@echo
	ln -s docker-compose_development.yml docker-compose.yml
	@sleep 2
endif
	mkdir -p certs
	mkdir -p httpd
	mkdir -p mig
	mkdir -p state
	mkdir -p log/migrid
	mkdir -p log/migrid-io
	mkdir -p log/migrid-openid
	mkdir -p log/migrid-sftp
	mkdir -p log/migrid-webdavs
	mkdir -p log/migrid-ftps
	sed 's@#unset @unset @g;s@#export @export @g' migrid-httpd.env > migrid-httpd-init.sh

up:
	${DOCKER_COMPOSE} up -d

down:
	${DOCKER_COMPOSE} down

dockerbuild: init
	${DOCKER_COMPOSE} build $(ARGS)

dockerclean:
	# remove latest image and dangling cache entries
	${DOCKER_COMPOSE} down || true
	${DOCKER} rmi -f $(OWNER)/$(IMAGE)${CONTAINER_TAG}
	# remove dangling images and build cache
	${DOCKER} image prune -f
	${DOCKER} builder prune -f

dockerpush:
	${DOCKER} push $(OWNER)/$(IMAGE)${CONTAINER_TAG}

clean:
	rm -fr ./mig
	rm -fr ./httpd

stateclean: warning
	rm -rf ./state

# IMPORTANT: this target is meant to reset the dir to a pristine checkout
#            and thus runs full clean up of even the state dir with user data
#            Be careful NOT to use it on production systems!
distclean: stateclean dockerclean clean
	rm -rf ./certs
	rm -rf ./log
        # TODO: is something like this still needed to clean up completely?
        # It needs to NOT greedily remove ALL local volumes if so!
        #if [ "$$(${DOCKER} volume ls -q -f 'name=${PACKAGE_NAME}*')" != "" ]; then\
        #	${DOCKER} volume rm -f $$(${DOCKER} volume ls -q -f 'name=${PACKAGE_NAME}*');\
        #fi
	rm -f .env docker-compose.yml

warning:
	@echo
	@echo "*** WARNING ***"
	@echo "*** Deleting ALL local state data ***"
	@echo
	@echo "Are you sure? [y/N]" && read ans && [ $${ans:-N} = y ]

test-doc:
	@shopt -s extglob; \
	for i in $$( grep -hv '\(^#.*\|^$$\)' !(migrid-httpd).env | sed -E 's!^([^=]*)=.*$$!\1!g' | sort | uniq ) ; do \
		grep -q "$$i" doc/source/sections/configuration/variables.rst \
		|| missing+=( "$$i" ) ; \
	done; \
	[ "$${#missing[@]}" != "0" ] && echo "ERROR: Missing documentation in doc/source/sections/configuration/variables.rst for:" \
	&& for i in $${missing[@]}; do \
		echo "  $$i"; \
	done && exit 1 \
	|| echo "OK: found all envionment variables in documentation" && exit 0

test:
	@cd tests; \
		export DOCKER=${DOCKER}; \
		err=0; \
		for test in test-*.sh ; do \
			bash ./$${test} || err=$$?; \
			if [ $$err != 0 ]; then \
				cat $${test}.log; \
				exit $$err; \
			fi; \
		done;
