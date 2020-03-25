+++
draft = false
date = 2020-03-19T20:43:53-04:00
title = "AWS Lambda: A Gift and a Curse"
slug = "lambda"
tags = []
+++

A few weeks ago I was procrastinating doing real work and decided to
run this site through [Mozilla
Observatory](https://observatory.mozilla.org/). It flagged a number of
missing no-brainer security headers. Naively, I assumed that adding
them would be a couple lines of [Terraform](https://terraform.io) code
and I'd be done.

What I found instead was that the common guidance is to add the
headers using a Lambda@Edge function. This was and remains astounding
to me. Rather than having settings on the CloudFront distribution or
S3 bucket for this common use case (adding HTTP headers to every
response), I had to write, test, and deploy my own code to add HTTP
headers.

The more I thought about it, the more I realized how common this
refrain is from AWS. Rather than adding a built-in, accessible feature
to one of their products the solution is "just use Lambda." While I
think that Lambda is a cool tool and make extensive use of it,
shifting the responsibility for implementing functionality onto the
user provides ample opportunities to introduce bugs. Especially in a
security-sensitive context this is not ideal.

At some level I can understand why: AWS products lack a uniform user
experience and what is simple and pleasant in one tool
(e.g. GuardDuty) can be a nightmare in others (the more advanced
features of S3 come to mind). Lambda lets customers build exactly what
they want and nothing more, avoiding the extra burden on the AWS team
to provide a UI for every possible use case.

However, at the same time the increased burden of writing code,
testing it, and monitoring it to ensure it does not break is exactly
why we pay the cost premium of using the cloud. Most of the time, we
outsource these tasks to Amazon. For 90% of what they provide, this is
totally worth it - RDS, ALBs, and ElastiCache reduce operational
overhead, provide better security, and have saved me tons of time
managing their respective functions. On the other hand, "just use a
lambda" is like going to a bakery, purchasing a loaf of bread and
being handed some dough and told to figure it out.

Fundamentally I think the root of this is feature sprawl in AWS. For
common tasks, there are usually 2 or 3 solutions that will work for a
given problem and usually a new one announced at re:Invent (see: SSM
Parameter Store and Secrets Manager). If AWS were more targeted in
what they delivered, there would not be a seemingly insurmountable
amount of features to build, and the highest-impact features could be
more effectively prioritized.

While this does sound very down on AWS, overall I think that they are
probably the least-wrong of the cloud providers in this regard. I
prefer that they be more extensible at the expense of engineering time
over GCP's "build an inscrutable UI for literally everything" or
Azure's "half-build a UI that doesn't have what you need." That said,
it is a balancing act to simplify and build common workflows in these
contexts because your customers all think that their use case is
simple, no matter how complex.
