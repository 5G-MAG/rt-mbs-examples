variable "OPEN5GS_MBS_VERSION" {
  default = "v2.7.1-mbs"
}

variable "SRSRAN_MBS_VERSION" {
  default = "test-mbs"
}

variable "OPEN5GS_BRANCH" {
  default = "upv-mbs"
}

variable "SRSRAN_PROJECT_BRANCH" {
  default = "upv-mbs"
}

variable "SRSRAN_4G_BRANCH" {
  default = "upv-mbs"
}

variable "UBUNTU_VERSION" {
  default = "jammy"
}

group "default" {
  targets = [
    "base-open5gs-dev", "mb-amf-dev", "mb-smf-dev", "mb-upf-dev", "af-dev",
    "base-srsran-project-dev", "base-srsran-4g-dev", "mb-gnb-dev", "mb-ue-dev", "gnuradio"
  ]
}

target "base-open5gs-dev" {
  context = "./images/base-open5gs-dev"
  tags = ["base-open5gs-dev:${OPEN5GS_MBS_VERSION}"]
  output = ["type=image"]
}

target "base-srsran-project-dev" {
  context = "./images/base-srsran-project-dev"
  tags = ["base-srsran-project-dev:${SRSRAN_MBS_VERSION}"]
  output = ["type=image"]
}

target "base-srsran-4g-dev" {
  context = "./images/base-srsran-4g-dev"
  tags = ["base-srsran-4g-dev:${SRSRAN_MBS_VERSION}"]
  output = ["type=image"]
}

target "mb-amf-dev" {
  context = "./images/mb-amf-dev"
  contexts = {
    "base-open5gs-dev:${OPEN5GS_MBS_VERSION}" = "target:base-open5gs-dev"
  }
  tags = ["mb-amf-dev:${OPEN5GS_MBS_VERSION}"]
  output = ["type=image"]
}

target "mb-smf-dev" {
  context = "./images/mb-smf-dev"
  contexts = {
    "base-open5gs-dev:${OPEN5GS_MBS_VERSION}" = "target:base-open5gs-dev"
  }
  tags = ["mb-smf-dev:${OPEN5GS_MBS_VERSION}"]
  output = ["type=image"]
}

target "mb-upf-dev" {
  context = "./images/mb-upf-dev"
  contexts = {
    "base-open5gs-dev:${OPEN5GS_MBS_VERSION}" = "target:base-open5gs-dev"
  }
  tags = ["mb-upf-dev:${OPEN5GS_MBS_VERSION}"]
  output = ["type=image"]
}

target "af-dev" {
  context = "./images/af-dev"
  tags = ["af-dev:${OPEN5GS_MBS_VERSION}"]
  output = ["type=image"]
}

target "gnuradio" {
  context = "./images/gnuradio"
  contexts = {
    "common" = "./images/common/"
  }
  tags = ["gnuradio:latest"]
  output = ["type=image"]
}

target "mb-gnb-dev" {
  context = "./images/mb-gnb-dev"
  contexts = {
    "base-srsran-project-dev:${SRSRAN_MBS_VERSION}" = "target:base-srsran-project-dev"
    "common" = "./images/common/"
  }
  tags = ["mb-gnb-dev:${SRSRAN_MBS_VERSION}"]
  output = ["type=image"]
}

target "mb-ue-dev" {
  context = "./images/mb-ue-dev"
  contexts = {
    "base-srsran-4g-dev:${SRSRAN_MBS_VERSION}" = "target:base-srsran-4g-dev"
    "common" = "./images/common/"
  }
  tags = ["mb-ue-dev:${SRSRAN_MBS_VERSION}"]
  output = ["type=image"]
}
