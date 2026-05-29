variable "FIVEG_MAG_MBS_VERSION" {
  default = "0.1.2"
}

variable "GITHUB_REGISTRY" {
  default = "ghcr.io/5g-mag"
}

variable "OPEN5GS_BRANCH" {
  default = "5mbs"
}

variable "SRSRAN_PROJECT_BRANCH" {
  default = "5mbs"
}

variable "SRSRAN_4G_BRANCH" {
  default = "5mbs-development"
}

variable "UBUNTU_VERSION" {
  default = "jammy"
}

group "default" {
  targets = [
    "base-mbs-open5gs", "amf_with_mbs", "smf_mb-smf", "upf_mb-upf", "test_mbs_af_as",
    "base-mbs-srsran-project", "base-mbs-srsran-4g", "gnb_with_mbs", "ue_with_mbs"
  ]
}

target "base-mbs-open5gs" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    OPEN5GS_BRANCH = "${OPEN5GS_BRANCH}"
  }
  context = "./images/base-mbs-open5gs"
  tags = ["base-mbs-open5gs:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}

target "base-mbs-srsran-project" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    SRSRAN_PROJECT_BRANCH = "${SRSRAN_PROJECT_BRANCH}"
  }
  context = "./images/base-mbs-srsran-project"
  tags = ["base-mbs-srsran-project:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
  ssh = ["default"]
}

target "base-mbs-srsran-4g" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    SRSRAN_4G_BRANCH = "${SRSRAN_4G_BRANCH}"
  }
  context = "./images/base-mbs-srsran-4g"
  tags = ["base-mbs-srsran-4g:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
  ssh = ["default"]
}

target "amf_with_mbs" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    FIVEG_MAG_MBS_VERSION = "${FIVEG_MAG_MBS_VERSION}"
  }
  context = "./images/amf_with_mbs"
  contexts = {
    "base-mbs-open5gs:${FIVEG_MAG_MBS_VERSION}" = "target:base-mbs-open5gs"
  }
  tags = ["amf_with_mbs:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}

target "smf_mb-smf" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    FIVEG_MAG_MBS_VERSION = "${FIVEG_MAG_MBS_VERSION}"
  }
  context = "./images/smf_mb-smf"
  contexts = {
    "base-mbs-open5gs:${FIVEG_MAG_MBS_VERSION}" = "target:base-mbs-open5gs"
  }
  tags = ["smf_mb-smf:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}

target "upf_mb-upf" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    FIVEG_MAG_MBS_VERSION = "${FIVEG_MAG_MBS_VERSION}"
  }
  context = "./images/upf_mb-upf"
  contexts = {
    "base-mbs-open5gs:${FIVEG_MAG_MBS_VERSION}" = "target:base-mbs-open5gs"
  }
  tags = ["upf_mb-upf:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}

target "test_mbs_af_as" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
  }
  context = "."
  dockerfile = "./images/test_mbs_af_as/Dockerfile"
  tags = ["test_mbs_af_as:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}

target "gnb_with_mbs" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    FIVEG_MAG_MBS_VERSION = "${FIVEG_MAG_MBS_VERSION}"
  }
  context = "./images/gnb_with_mbs"
  contexts = {
    "base-mbs-srsran-project:${FIVEG_MAG_MBS_VERSION}" = "target:base-mbs-srsran-project"
  }
  tags = ["gnb_with_mbs:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}

target "ue_with_mbs" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    FIVEG_MAG_MBS_VERSION = "${FIVEG_MAG_MBS_VERSION}"
  }
  context = "./images/ue_with_mbs"
  contexts = {
    "base-mbs-srsran-4g:${FIVEG_MAG_MBS_VERSION}" = "target:base-mbs-srsran-4g"
  }
  tags = ["ue_with_mbs:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}
