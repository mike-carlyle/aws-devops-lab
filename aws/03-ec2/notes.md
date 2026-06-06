# EC2: Elastic Compute Cloud

## What this section covered

EC2 is AWS's core compute service, virtual servers running in the cloud. This was the biggest section so far and went well beyond just launching instances. It covered the full picture: networking, storage, and how to build something that actually scales and stays available.

---

## Instance Types

EC2 instances come in different families, each optimised for a different type of workload.

| Family | Optimised For | Example Use Case |
|--------|--------------|-----------------|
| t3, t4g | General purpose, burstable | Dev environments, low-traffic apps |
| c6i | Compute | High-performance web servers, batch processing |
| r6g | Memory | Databases, in-memory caches |
| p3, g4 | GPU | Machine learning, video rendering |

In practice, t3 instances are fine for learning and dev work. The families matter more when you're sizing production workloads or trying to optimise costs.

---

## SSH Access

SSH is how you connect to a Linux EC2 instance. The process:

1. Assign a key pair when launching the instance. AWS stores the public key and you download the private key as a .pem file.
2. Connect with: `ssh -i "keypair.pem" ec2-user@<public-ip>`
3. The instance's security group needs to allow inbound traffic on port 22.

I did this using CloudShell rather than a local terminal, which worked well and didn't require anything installed locally.

---

## IP Addressing

This tripped me up at first so it's worth being clear on:

| Type | What it is | Survives a stop/start? |
|------|------------|----------------------|
| Private IP | Internal AWS network address | Yes |
| Public IP | Internet-facing, dynamically assigned | No, changes on restart |
| Elastic IP | Static public IP you allocate to your account | Yes |

If you're pointing a DNS record at an instance, you need an Elastic IP or the address changes every time you restart. That said, Elastic IPs cost money when they're allocated but not attached to a running instance, so release them when not in use.

---

## ENIs

An Elastic Network Interface is a virtual network card. Every EC2 instance has at least one. They can be detached from one instance and attached to another, which is useful in failover scenarios where you need to move a network identity quickly without changing DNS or IP configuration.

---

## EBS

EBS volumes are persistent block storage, essentially a hard drive you attach to an EC2 instance. A few things that matter:

- EBS volumes live in a specific AZ, so an instance and its EBS volume need to be in the same AZ
- The volume persists independently of the instance. Stop the instance and the data is still there.
- Different volume types for different needs: gp3 for general use, io2 for high performance databases, st1 for large sequential reads

In the lab I attached an additional EBS volume to a running instance, formatted it, and mounted it. It's a good way to see that storage and compute are genuinely separate things in AWS.

---

## AMIs

An AMI is a snapshot of an EC2 instance. The OS, installed software, and configuration are all captured at a point in time. You can use it to launch new instances that start from that exact state.

Useful for spinning up pre-configured servers quickly, creating a standard base image for your team, or copying a working setup to another region.

---

## EFS

EFS is a managed network file system. Unlike EBS which attaches to one instance, EFS can be mounted on multiple instances at the same time across multiple AZs.

The clearest way I think about the difference:

- EBS is like a USB drive, plugged into one machine at a time
- EFS is like a network share where multiple machines can access it simultaneously and it scales automatically

Typical use case: a web application running across several EC2 instances that all need to read and write to the same files.

---

## Security Groups

Security groups are the virtual firewalls for EC2 instances. They control what traffic is allowed in and out at the instance level.

A few things worth knowing:

- Rules are allow-only. There's no explicit deny, so if there's no rule allowing something it's blocked.
- They're stateful, meaning if inbound traffic is allowed the response is automatically allowed back out. This is different from Network ACLs which are stateless.
- You can reference other security groups in rules rather than hardcoding IP addresses, which is useful for letting application servers talk to database servers without specifying IPs.

In the labs I set up groups to allow SSH on port 22 and HTTP on port 80 while blocking everything else.

---

## Elastic Load Balancers

Load balancers sit in front of your EC2 instances and distribute incoming traffic across them. There are three types:

| Type | Use Case |
|------|----------|
| ALB (Application) | HTTP/HTTPS, path-based routing, microservices |
| NLB (Network) | Very high performance, TCP/UDP |
| CLB (Classic) | Legacy, avoid for anything new |

For most web applications the ALB is what you'd use. It can route traffic based on the URL path, which is what makes it useful for microservices. Load balancers also run health checks and only route traffic to instances that are actually responding correctly.

---

## Auto Scaling Groups

ASGs automatically adjust how many EC2 instances are running based on demand. You set three numbers:

- Minimum: never go below this
- Desired: the target number of instances
- Maximum: never go above this

Scaling policies define what triggers a scale out or in event. A common one is CPU utilisation, so if average CPU across your instances goes above 70% it adds more instances.

The real power is ASG combined with an ELB. New instances automatically register with the load balancer and terminated instances are automatically deregistered. The whole thing runs without manual intervention.

---

## What I built in the labs

- Launched EC2 instances with different configurations
- Connected via SSH from CloudShell
- Attached and mounted an additional EBS volume
- Created an AMI from a running instance
- Set up security groups for HTTP and SSH access
- Explored ELB and ASG configuration in the console

---

## What I took from this section

The separation of compute and storage is a pattern that keeps coming up in AWS. EC2 and EBS scale and are billed independently. That's a different mental model from a physical server where everything is bundled together.

The stateful vs stateless distinction for security groups vs NACLs is an exam topic that's also genuinely useful to understand. Getting it wrong in production means traffic not flowing as expected.

ASG and ELB together are more than the sum of their parts. Either one alone is useful but the combination is what makes a properly resilient application.
