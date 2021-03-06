# vi:syntax=python

load("github.com/mesosphere/dispatch-catalog/starlark/stable/pipeline@master", "clean", "imageResource")

__doc__ = """
# Kaniko

Provides methods for building Docker containers using Kaniko.

Import URL: `github.com/mesosphere/dispatch-catalog/starlark/stable/kaniko`
"""

def kaniko(git, image, context="", dockerfile="Dockerfile", **kwargs):
    """
    Build a Docker image using Kaniko.
    """
    imageWithTag = "{}:$(context.build.name)".format(image)
    name = clean(image)
    additional_inputs = kwargs.get("inputs",[])
    imageResource(name,
        url=imageWithTag,
        digest="$(inputs.resources.{}.digest)".format(name))

    build_args = []

    for k, v in kwargs.get("buildArgs", {}).items():
        build_args.append("--build-arg={}={}".format(k, v))

    task(name, inputs = [git]+additional_inputs, outputs = [name], steps=[
        v1.Container(
            name = "docker-build",
            image = "chhsiao/kaniko-executor",
            args= build_args+[
                "--destination={}".format(imageWithTag),
                "--context=/workspace/{}/{}".format(git, context),
                "--oci-layout-path=/workspace/output/{}".format(name),
                "--dockerfile=/workspace/{}/{}".format(git, dockerfile)
            ])])

    return name
