module "qa" {
    source = "../modules/web"

    environment = {
        name           = "qa"
        network_prefix = "10.2"
    }

    asg_min_size = 1
    asg_max_size = 1
}