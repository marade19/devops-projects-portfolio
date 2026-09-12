# Security Notes

## Never commit AWS credentials

Do not commit:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- Private SSH keys
- `.pem` files
- AWS account secrets
- Passwords
- API tokens

Use IAM roles for EC2 whenever possible.

## Replace placeholders

Before reusing the scripts, replace:

- `YOUR-USERNAME`
- `YOUR-REPOSITORY`
- `YOUR-PROJECT-BUCKET`

with values from your own environment.

## IAM policy scope

The S3 example policy is intentionally scoped to one bucket instead of granting:

```text
s3:*
```

to all buckets.

For production, permissions should be reviewed and reduced to exactly what the application needs.
