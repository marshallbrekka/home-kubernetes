ARTIFACT_DIR=artifacts
BUILD_DIR=build

.PHONY: docker-build-image
docker-build-image:
	docker build -t home-kubernetes-builder:latest $(BUILD_DIR)/docker

run-docker: docker-build-image
	docker run \
         -it \
	       --privileged \
         --volume $$(pwd):/home_kubernetes \
         --workdir /home_kubernetes \
         home-kubernetes-builder:latest $(ARGS)
