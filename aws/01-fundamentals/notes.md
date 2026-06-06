# AWS Fundamentals

## What this section covered

Before touching any AWS service it's worth understanding how AWS is physically structured. Every decision about where to deploy resources depends on this, so it made sense to start here.

---

## Regions

A region is a physical geographic area where AWS runs its infrastructure. Each one has a name and a code, so EU (London) is eu-west-2 and US East (N. Virginia) is us-east-1. When you create any resource in AWS, you're creating it in a specific region.

A few things that actually matter when picking a region: latency (closer to your users is better), data residency (some industries and countries require data to stay within certain borders), and service availability (not every AWS service exists in every region yet).

For most of my learning I've been working in eu-west-2 since I'm based in the UK.

---

## Availability Zones

Within each region there are multiple availability zones. These are physically separate data centres that are close enough to have fast connections between them but far enough apart that a fire or power failure in one won't take down another.

eu-west-2 for example has eu-west-2a, eu-west-2b, and eu-west-2c.

This matters because it's the foundation of high availability in AWS. If you deploy your application across two or three AZs, one going down doesn't mean your users notice anything. This concept comes up constantly throughout the course, particularly with load balancers and auto scaling.

---

## The AWS Console

The console is the web UI for AWS. A few things worth noting:

The region selector sits in the top right corner and it's easy to accidentally work in the wrong region, then wonder where your resources are. I made this mistake early on.

Some services are global rather than regional. IAM and Route 53 are the main ones. Most others are regional, so keeping an eye on the region selector matters.

The console is great for learning and exploration but it doesn't scale. Clicking through menus to build infrastructure isn't repeatable or auditable. That's why Infrastructure as Code (Terraform, CloudFormation) is important for real work.

---

## What I took from this section

Understanding regions and AZs isn't just exam knowledge. It directly affects every architecture decision you make. Where do I put this database? Should I deploy to one AZ or three? What happens if this region goes down? These questions come up throughout the rest of the course and in real-world design.
