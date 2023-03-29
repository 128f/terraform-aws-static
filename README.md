#### Static site aws

A set of terraform files to host a static site on aws.

As simple as I can make it.

Purchase your domain on aws, and then run `terraform apply`,
enter your domain name when prompted, and you're done!

This will purchase SSL certs, create a bucket and a cloudfront.
After that, just upload to the bucket.
