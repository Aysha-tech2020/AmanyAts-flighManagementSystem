provider "aws" {
  region = "eu-north-1" # Adjust to your AWS region
}

# Data source to retrieve the AWS account ID
data "aws_caller_identity" "current" {}

# Reference the existing IAM Role
data "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role" # Existing role
}

# Lambda Function for Search Flights
resource "aws_lambda_function" "searchFlights" {
  function_name = "searchFlights"
  role          = data.aws_iam_role.lambda_execution_role.arn
  handler       = "search-handler.searchFlights"
  runtime       = "python3.9"
  filename      = "${path.module}/search-handler.zip"

  environment {
    variables = {
      DYNAMODB_TABLE = "Flights" # Ensure this matches your DynamoDB table name
    }
  }

  tags = {
    Environment = "dev"
  }
}

# Lambda Function for Booking Service
resource "aws_lambda_function" "booking_service" {
  function_name = "bookingService"
  role          = data.aws_iam_role.lambda_execution_role.arn
  handler       = "booking-handler.bookFlight"
  runtime       = "python3.9"
  filename      = "${path.module}/booking-handler.zip"

  environment {
    variables = {
      BOOKINGS_TABLE = "Bookings" # DynamoDB table for bookings
      FLIGHTS_TABLE  = "Flights"  # DynamoDB table for flights
    }
  }

  tags = {
    Environment = "dev"
  }
}

# Use the same REST API
resource "aws_api_gateway_rest_api" "flight_management_api" {
  name = "flightManagementAPIs"
}

# API Gateway Resource for /searchFlights
resource "aws_api_gateway_resource" "searchFlights_resource" {
  rest_api_id = aws_api_gateway_rest_api.flight_management_api.id
  parent_id   = aws_api_gateway_rest_api.flight_management_api.root_resource_id
  path_part   = "searchFlights"
}

# API Gateway Method for GET /searchFlights
resource "aws_api_gateway_method" "get_searchFlights" {
  rest_api_id   = aws_api_gateway_rest_api.flight_management_api.id
  resource_id   = aws_api_gateway_resource.searchFlights_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway Integration with Lambda for Search Flights
resource "aws_api_gateway_integration" "searchFlights_integration" {
  rest_api_id             = aws_api_gateway_rest_api.flight_management_api.id
  resource_id             = aws_api_gateway_resource.searchFlights_resource.id
  http_method             = aws_api_gateway_method.get_searchFlights.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.searchFlights.invoke_arn
}

# API Gateway Resource for /bookFlight
resource "aws_api_gateway_resource" "bookFlight_resource" {
  rest_api_id = aws_api_gateway_rest_api.flight_management_api.id
  parent_id   = aws_api_gateway_rest_api.flight_management_api.root_resource_id
  path_part   = "bookFlight"
}

# API Gateway Method for POST /bookFlight
resource "aws_api_gateway_method" "post_bookFlight" {
  rest_api_id   = aws_api_gateway_rest_api.flight_management_api.id
  resource_id   = aws_api_gateway_resource.bookFlight_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration with Lambda for Booking Service
resource "aws_api_gateway_integration" "bookFlight_integration" {
  rest_api_id             = aws_api_gateway_rest_api.flight_management_api.id
  resource_id             = aws_api_gateway_resource.bookFlight_resource.id
  http_method             = aws_api_gateway_method.post_bookFlight.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.booking_service.invoke_arn
}

# Lambda Permission for API Gateway (Search Flights)
resource "aws_lambda_permission" "apigw_invoke_search" {
  statement_id  = "AllowAPIGatewayInvokeSearch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.searchFlights.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:eu-north-1:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.flight_management_api.id}/*/*"
}

# Lambda Permission for API Gateway (Booking Service)
resource "aws_lambda_permission" "apigw_invoke_booking" {
  statement_id  = "AllowAPIGatewayInvokeBooking"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.booking_service.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:eu-north-1:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.flight_management_api.id}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.flight_management_api.id
  stage_name  = "dev"

  depends_on = [
    aws_api_gateway_integration.searchFlights_integration,
    aws_api_gateway_integration.bookFlight_integration
  ]
}

# Output the API Gateway endpoints
output "search_api_endpoint" {
  value = "${aws_api_gateway_deployment.api_deployment.invoke_url}searchFlights"
}

output "booking_api_endpoint" {
  value = "${aws_api_gateway_deployment.api_deployment.invoke_url}bookFlight"
}