resource "aws_ecr_repository" "producer" {
  name = "${var.name}-producer"
  # The producer task definition deliberately uses latest: it is an on-demand
  # load generator, not the continuously deployed service.
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  tags = local.tags
}

resource "aws_ecr_repository" "consumer" {
  name                 = "${var.name}-consumer"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "images" {
  for_each   = { producer = aws_ecr_repository.producer.name, consumer = aws_ecr_repository.consumer.name }
  repository = each.value
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 20 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
