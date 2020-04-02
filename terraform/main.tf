variable "token" {
  type = string
}

variable "cloud_id" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "zone" {
  type = string
  default = "ru-central1-b"
}

variable "endpoint" {
  default = "api.cloud.yandex.net:443"
}

variable "storage_endpoint" {
  default = "storage.yandexcloud.net"
}

provider "yandex" {
  token            = var.token
  cloud_id         = var.cloud_id
  folder_id        = var.folder_id
  zone             = var.zone
  endpoint         = var.endpoint
  storage_endpoint = var.storage_endpoint
}

resource "yandex_iam_service_account" "tf-dataproc-sa" {
  name        = "mongospark"
  description = "service account to manage Dataproc Cluster created by Terraform"
}

resource "yandex_resourcemanager_folder_iam_binding" "dataproc-manager" {
  folder_id = var.folder_id

  role = "mdb.dataproc.agent"

  members = [
    "serviceAccount:${yandex_iam_service_account.tf-dataproc-sa.id}",
  ]
}

// required in order to create bucket
resource "yandex_resourcemanager_folder_iam_binding" "bucket-creator" {
  folder_id = var.folder_id

  role = "editor"

  members = [
    "serviceAccount:${yandex_iam_service_account.tf-dataproc-sa.id}",
  ]
}

resource "yandex_vpc_network" "tf-dataproc-net" {
  name = "mongospark"
}

resource "yandex_vpc_subnet" "tf-dataproc-subnet" {
  name           = "mongospark"
  zone           = var.zone
  network_id     = yandex_vpc_network.tf-dataproc-net.id
  v4_cidr_blocks = ["10.1.0.0/24"]
}

resource "yandex_iam_service_account_static_access_key" "tf-dataproc-sa-static-key" {
  service_account_id = yandex_iam_service_account.tf-dataproc-sa.id
  description        = "static access key for object storage"

  depends_on = [
    yandex_resourcemanager_folder_iam_binding.bucket-creator
  ]
}

resource "yandex_storage_bucket" "tf-dataproc" {
  bucket     = "mongospark"
  access_key = yandex_iam_service_account_static_access_key.tf-dataproc-sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.tf-dataproc-sa-static-key.secret_key
}

resource "yandex_dataproc_cluster" "tf-dataproc-cluster" {
  depends_on = [yandex_resourcemanager_folder_iam_binding.dataproc-manager]

  bucket      = yandex_storage_bucket.tf-dataproc.bucket
  description = "Dataproc Cluster to test Spark + Mongo"
  name        = "mongospark"
  service_account_id = yandex_iam_service_account.tf-dataproc-sa.id

  cluster_config {
    version_id = "1.1"

    hadoop {
      services = ["HDFS", "YARN", "SPARK", "MAPREDUCE"]
      properties = {
        "yarn:yarn.resourcemanager.am.max-attempts" = 5
      }
      ssh_public_keys = [
      file("~/.ssh/id_rsa.pub")]
    }

    subcluster_spec {
      name = "main"
      role = "MASTERNODE"
      resources {
        resource_preset_id = "s2.small"
        disk_type_id       = "network-hdd"
        disk_size          = 32
      }
      subnet_id   = yandex_vpc_subnet.tf-dataproc-subnet.id
      hosts_count = 1
    }

    subcluster_spec {
      name = "data"
      role = "DATANODE"
      resources {
        resource_preset_id = "s2.small"
        disk_type_id       = "network-hdd"
        disk_size          = 32
      }
      subnet_id   = yandex_vpc_subnet.tf-dataproc-subnet.id
      hosts_count = 2
    }
  }
}

resource "yandex_mdb_mongodb_cluster" "foo" {
  name        = "mongospark"
  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.tf-dataproc-net.id

  cluster_config {
    version = "4.2"
  }

  database {
    name = "mongospark"
  }

  user {
    name     = "spark"
    password = "password"
    permission {
      database_name = "mongospark"
    }
  }

  resources {
    resource_preset_id = "s2.small"
    disk_size          = 200
    disk_type_id       = "network-ssd"
  }

  host {
    zone_id   = "ru-central1-b"
    subnet_id = yandex_vpc_subnet.tf-dataproc-subnet.id
  }
}

resource "yandex_compute_instance" "gateway" {
  name = "mongospark-gateway"

  resources {
    cores  = 2
    memory = 8
  }

  boot_disk {
    initialize_params {
      image_id = "fd83bj827tp2slnpp7f0" # Ubuntu 18.04
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.tf-dataproc-subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }
}

output "gateway_ip" {
  value = yandex_compute_instance.gateway.network_interface.0.nat_ip_address
}
