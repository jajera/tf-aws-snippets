resource "aws_iam_group" "group1" {
  name = "example_group1"
}

resource "aws_iam_group" "group2" {
  name = "example_group2"
}

resource "aws_iam_group" "group3" {
  name = "example_group3"
}

resource "aws_iam_group" "group4" {
  name = "example_group4"
}

resource "aws_iam_group" "group5" {
  name = "example_group5"
}

resource "aws_iam_group" "group6" {
  name = "example_group6"
}

resource "aws_iam_group" "group7" {
  name = "example_group7"
}

resource "aws_iam_group" "group8" {
  name = "example_group8"
}

resource "aws_iam_group" "group9" {
  name = "example_group9"
}

resource "aws_iam_group" "group10" {
  name = "example_group10"
}

resource "aws_iam_group" "group11" {
  name = "example_group11"
}

resource "aws_iam_user" "user1" {
  name = "example_user1"
}

resource "aws_iam_user_group_membership" "example" {
  user = aws_iam_user.user1.name

  groups = [
    aws_iam_group.group1.name,
    aws_iam_group.group2.name,
    aws_iam_group.group3.name,
    aws_iam_group.group4.name,
    aws_iam_group.group5.name,
    aws_iam_group.group6.name,
    aws_iam_group.group7.name,
    aws_iam_group.group8.name,
    aws_iam_group.group9.name,
    aws_iam_group.group10.name
  ]
}

# expected to fail
resource "aws_iam_user_group_membership" "fail" {
  user = aws_iam_user.user1.name

  groups = [
    aws_iam_group.group11.name
  ]

  depends_on = [
    aws_iam_user_group_membership.example
  ]
}
