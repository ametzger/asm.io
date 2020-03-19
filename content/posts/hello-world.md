+++
draft = false
date = 2020-03-19T15:45:06-04:00
title = "Hello, World!"
description = ""
slug = "hello-world"
tags = []
categories = []
externalLink = ""
series = []
+++

Howdy! This is my blog. As this is my first post, I thought I'd
describe how it is set up and what is good/bad about it.

### Hugo

The blog itself is built with the [Hugo](https://gohugo.io) static
site generator. I like it because it allows me to cobble together my
own version of a tool like Medium and spend copious time messing
around with glue code. The availability of pre-built themes also saves
me from having to remember how bad I am at frontend development.

### AWS

asm.io is hosted using AWS S3 and CloudFront. I have the
infrastructure for the site managed using
[Terraform](https://terraform.io). I use Terraform quite a bit in [my
day job](https://jellyfish.co) and I have come to love its
quirkiness. Regardless of the tool, infrastructure as code has proven
to be a really worthwhile investment both personally and
professionally.

S3/CloudFront also minimizes hosting cost: I usually pay less than
$2/month for hosting, and it can scale rapidly should the need arise.

If you're interested in seeing how asm.io is deployed, please check
out [the Git
repo](https://github.com/ametzger/asm.io/tree/master/infra).

### GitLab CI

The site uses `make` for common tasks (e.g. local builds, deploying)
which is further automated using GitLab CI. GitLab handles building
and deploying changes automatically so I can prototype locally, push a
commit, and have everything taken care of.

I'm not totally in love with GitLab, I implemented this prior to the
general availability of GitHub Actions. If I have some spare time, I
might port over to use that instead.

### Conclusion

I hope this has been at least moderately interesting. Generally, I am
quite pleased with this setup for my personal site both from a
personal desire to have something to putz with in my spare time and
not cost a ton of money. If you're so inclined, please check out [the
repo](https://github.com/ametzger/asm.io).
