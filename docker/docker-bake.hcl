variable "FIVEG_MAG_MBS_VERSION" {
  default = "0.1.4"
}

variable "OPEN5GS_VERSION" {
  default = "v2.7.7"
}

variable "MONGODB_VERSION" {
  default = "6.0"
}

variable "NODE_VERSION" {
  default = "20"
}

variable "GITHUB_USER" {
  default = "YOUR_USER"
}

variable "GITHUB_TOKEN" {
  default = "YOUR_PAT"
}

variable "GITHUB_REGISTRY" {
  default = "ghcr.io/5g-mag"
}

variable "OPEN5GS_BRANCH" {
  default = "v2.7.7"
}

variable "OPEN5GS_MBS_BRANCH" {
  default = "5mbs"
}

variable "SRSRAN_MBS_PROJECT_BRANCH" {
  default = "5mbs-development"
}

variable "SRSRAN_4G_MBS_BRANCH" {
  default = "5mbs-development"
}

variable "UBUNTU_VERSION" {
  default = "jammy"
}

group "default" {
  targets = [
    // Core Platform Base Layers
    "base-open5gs", "base-mbs-open5gs", "base-mbs-srsran-project", "base-mbs-srsran-4g",
    
    // Individual Baseline Open5GS Functions
    "amf", "ausf", "bsf", "nrf", "nssf", "pcf", "scp", "sepp", "smf", "udm", "udr", "upf", "webui",
    
    // Custom 5G Functions
    "nrf_5gmag",
    
    // Custom 5G-MBS Functions & RAN Stacks
    "amf_with_mbs", "smf_mb-smf", "upf_mb-upf", "test_mbs_af_as", "gnb_with_mbs", "ue_with_mbs"
  ]
}

// -----------------------------------------------------------------------------
// BASE COMPILATION PLATFORMS
// -----------------------------------------------------------------------------
target "base-open5gs" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    OPEN5GS_BRANCH = "${OPEN5GS_BRANCH}"
  }
  context = "./images/base-open5gs"
  tags = [
    "${GITHUB_REGISTRY}/base-open5gs:${OPEN5GS_VERSION}"
  ]
  output = ["type=image"]
}

target "base-mbs-open5gs" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
    OPEN5GS_MBS_BRANCH = "${OPEN5GS_MBS_BRANCH}"
  }
  context = "./images/base-mbs-open5gs"
  tags = [
    "${GITHUB_REGISTRY}/base-mbs-open5gs:${FIVEG_MAG_MBS_VERSION}",
  ]
  output = ["type=image"]
}

target "base-mbs-srsran-project" {
  args = {
    UBUNTU_VERSION        = "${UBUNTU_VERSION}"
    SRSRAN_PROJECT_BRANCH = "${SRSRAN_MBS_PROJECT_BRANCH}"
    GITHUB_USER           = "${GITHUB_USER}"
    GITHUB_TOKEN          = "${GITHUB_TOKEN}"
  }
  context = "./images/base-mbs-srsran-project"
  tags = [
    "${GITHUB_REGISTRY}/base-mbs-srsran-project:${FIVEG_MAG_MBS_VERSION}"
  ]
  output = ["type=image"]
}

target "base-mbs-srsran-4g" {
  args = {
    UBUNTU_VERSION   = "${UBUNTU_VERSION}"
    SRSRAN_4G_BRANCH = "${SRSRAN_4G_MBS_BRANCH}"
    GITHUB_USER      = "${GITHUB_USER}"
    GITHUB_TOKEN     = "${GITHUB_TOKEN}"
  }
  context = "./images/base-mbs-srsran-4g"
  tags = [
    "${GITHUB_REGISTRY}/base-mbs-srsran-4g:${FIVEG_MAG_MBS_VERSION}"
  ]
  output = ["type=image"]
}

// -----------------------------------------------------------------------------
// INDIVIDUAL OPEN5GS BASELINE CORE FUNCTIONS
// -----------------------------------------------------------------------------
target "amf" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/amf"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/amf:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "ausf" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/ausf"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/ausf:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "bsf" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/bsf"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/bsf:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "nrf" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/nrf"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/nrf:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "nssf" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/nssf"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/nssf:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "pcf" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/pcf"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/pcf:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "scp" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/scp"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/scp:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "sepp" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/sepp"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/sepp:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "smf" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/smf"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/smf:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "udm" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/udm"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/udm:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "udr" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/udr"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/udr:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "upf" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
  }
  context = "./images/upf"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/upf:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

target "webui" {
  args = {
    UBUNTU_VERSION  = "${UBUNTU_VERSION}"
    OPEN5GS_VERSION = "${OPEN5GS_VERSION}"
    NODE_VERSION    = "${NODE_VERSION}"
  }
  context = "./images/webui"
  contexts = {
    "base-open5gs:${OPEN5GS_VERSION}" = "target:base-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/webui:${OPEN5GS_VERSION}"]
  output = ["type=image"]
}

// -----------------------------------------------------------------------------
// CUSTOM 5G-MAG EXTENSION FUNCTIONS
// -----------------------------------------------------------------------------
target "nrf_5gmag" {
  args = {
    UBUNTU_VERSION        = "${UBUNTU_VERSION}"
    FIVEG_MAG_MBS_VERSION = "${FIVEG_MAG_MBS_VERSION}"
  }
  context = "./images/nrf_5gmag"
  contexts = {
    "base-mbs-open5gs:${FIVEG_MAG_MBS_VERSION}" = "target:base-mbs-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/nrf_5gmag:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}

// -----------------------------------------------------------------------------
// CUSTOM 5G-MBS EXTENSION FUNCTIONS
// -----------------------------------------------------------------------------

target "amf_with_mbs" {
  args = {
    UBUNTU_VERSION        = "${UBUNTU_VERSION}"
    FIVEG_MAG_MBS_VERSION = "${FIVEG_MAG_MBS_VERSION}"
  }
  context = "./images/amf_with_mbs"
  contexts = {
    "base-mbs-open5gs:${FIVEG_MAG_MBS_VERSION}" = "target:base-mbs-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/amf_with_mbs:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}

target "smf_mb-smf" {
  args = {
    UBUNTU_VERSION        = "${UBUNTU_VERSION}"
    FIVEG_MAG_MBS_VERSION = "${FIVEG_MAG_MBS_VERSION}"
  }
  context = "./images/smf_mb-smf"
  contexts = {
    "base-mbs-open5gs:${FIVEG_MAG_MBS_VERSION}" = "target:base-mbs-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/smf_mb-smf:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}

target "upf_mb-upf" {
  args = {
    UBUNTU_VERSION        = "${UBUNTU_VERSION}"
    FIVEG_MAG_MBS_VERSION = "${FIVEG_MAG_MBS_VERSION}"
  }
  context = "./images/upf_mb-upf"
  contexts = {
    "base-mbs-open5gs:${FIVEG_MAG_MBS_VERSION}" = "target:base-mbs-open5gs"
  }
  tags   = ["${GITHUB_REGISTRY}/upf_mb-upf:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}

target "test_mbs_af_as" {
  args = {
    UBUNTU_VERSION = "${UBUNTU_VERSION}"
  }
  context    = "."
  dockerfile = "./images/test_mbs_af_as/Dockerfile"
  tags       = ["${GITHUB_REGISTRY}/test_mbs_af_as:${FIVEG_MAG_MBS_VERSION}"]
  output     = ["type=image"]
}

target "gnb_with_mbs" {
  args = {
    UBUNTU_VERSION        = "${UBUNTU_VERSION}"
    FIVEG_MAG_MBS_VERSION = "${FIVEG_MAG_MBS_VERSION}"
  }
  context = "./images/gnb_with_mbs"
  contexts = {
    "base-mbs-srsran-project:${FIVEG_MAG_MBS_VERSION}" = "target:base-mbs-srsran-project"
  }
  tags   = ["${GITHUB_REGISTRY}/gnb_with_mbs:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}

target "ue_with_mbs" {
  args = {
    UBUNTU_VERSION        = "${UBUNTU_VERSION}"
    FIVEG_MAG_MBS_VERSION = "${FIVEG_MAG_MBS_VERSION}"
  }
  context = "./images/ue_with_mbs"
  contexts = {
    "base-mbs-srsran-4g:${FIVEG_MAG_MBS_VERSION}" = "target:base-mbs-srsran-4g"
  }
  tags   = ["${GITHUB_REGISTRY}/ue_with_mbs:${FIVEG_MAG_MBS_VERSION}"]
  output = ["type=image"]
}
