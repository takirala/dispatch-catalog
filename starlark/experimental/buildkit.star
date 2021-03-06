# vi:syntax=python

load("github.com/mesosphere/dispatch-catalog/starlark/stable/pipeline@master", "clean", "imageResource", "volume")

__doc__ = """
# Buildkit

Provides methods for interacting with a Buildkit instance.

Import URL: `github.com/mesosphere/dispatch-catalog/starlark/experimental/buildkit`
"""

def buildkitContainer(name, image, workingDir, command, output=True, **kwargs):
    """
    buildkitContainer returns a Kubernetes corev1.Container that runs inside of buildkit.
    The container can take advantage of buildkit's cache mount feature as the cache is mounted into /cache.
    """

    envStr = ""

    for envVar in kwargs.get("env", []):
        envStr += "ENV {} {}\n".format(envVar.name, envVar.value)

    dockerfile = """
cat > /tmp/Dockerfile.buildkit <<EOF
# syntax = docker/dockerfile:experimental
FROM {image}
WORKDIR {workingDir}
ENV GOCACHE /cache/go-cache
ENV GOPATH /cache/go
ENV DOCKER_CONFIG /tekton/home/.docker
{envStr}
ADD /tekton/home/.docker /tekton/home/.docker
"""

    if output:
        dockerfile += "ADD /workspace/output/ /workspace/output/"

    dockerfile += """
ADD {workingDir} {workingDir}
RUN --mount=type=cache,target=/cache {command}
FROM scratch
"""

    if output:
        dockerfile += "COPY --from=0 /workspace/output/ /workspace/output/"

    dockerfile += """
COPY --from=0 {workingDir} {workingDir}
EOF
buildctl --debug --addr=tcp://buildkitd.buildkit:1234 build --progress=plain --frontend=dockerfile.v0 \
    --opt filename=Dockerfile.buildkit --local context=/ --local dockerfile=/tmp/ --output type=local,dest=/
"""

    return k8s.corev1.Container(
        name = name,
        image = "moby/buildkit:v0.6.2",
        workingDir = workingDir,
        command = [
            "sh", "-c", dockerfile.format(envStr=envStr, name=name, workingDir=workingDir, image=image, command=command)
        ],
        **kwargs)

def buildkit(git, image, context=".", dockerfile="Dockerfile", tag="$(context.build.name)", **kwargs):
    """
    Build a Docker image using Buildkit.
    """
    imageWithTag = "{}:{}".format(image, tag)
    name = clean(image)
    build_args = []
    additional_inputs = kwargs.get("inputs",[])
    for k, v in kwargs.get("buildArgs", {}).items():
      build_args += ["--opt", "build-arg:{}={}".format(k, v)]

    imageResource(name,
        url=image,
        digest="$(inputs.resources.{}.digest)".format(name))

    task(name, inputs = [git]+additional_inputs, outputs = [name], steps=[
        k8s.corev1.Container(
            name = "build",
            image = "moby/buildkit:v0.6.2",
            workingDir = "/workspace/{}/".format(git),
            command = ["buildctl", "--debug",
                  "--addr=tcp://buildkitd.buildkit:1234", "build",
                  "--progress=plain", "--frontend=dockerfile.v0",
                  "--opt", "filename={}".format(dockerfile)] + build_args
                  + ["--local", "context={}".format(context), "--local", "dockerfile=.",
                  "--output", "type=docker,dest=/wd/image.tar",
                  "--export-cache", "type=inline",
                  "--import-cache", "type=registry,ref={}".format(imageWithTag)],
            volumeMounts = [ k8s.corev1.VolumeMount(name="wd", mountPath="/wd") ]
        ),
        k8s.corev1.Container(
            name = "extract",
            image = "mesosphere/skopeo:pr-427",
            command = ["tar", "-xf", "/wd/image.tar", "-C", "/workspace/output/{}/".format(name)],
            volumeMounts = [ k8s.corev1.VolumeMount(name="wd", mountPath="/wd") ]
        ),
        k8s.corev1.Container(
            name = "push",
            image = "mesosphere/skopeo:pr-427",
            command = ["skopeo", "copy", "oci:/workspace/output/{}/".format(name), "docker://{}".format(imageWithTag)]
        ),
    ], volumes = [ volume("wd", emptyDir=k8s.corev1.EmptyDirVolumeSource()) ])

    return name

