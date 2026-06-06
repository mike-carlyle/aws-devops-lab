# IAM: Identity and Access Management

## What this section covered

IAM is how AWS handles identity and permissions. It controls who can access your account and what they're allowed to do. This came before EC2 in the course deliberately, because getting security right from the start is the right approach and the root account should never be used for day-to-day work.

---

## Users

An IAM user represents a person or application interacting with AWS. Each user gets their own credentials and their own set of permissions.

The first thing I did was create a personal IAM user for all my lab work and stopped using the root account. The root account has unrestricted access to everything including billing, so it should be locked down and only touched when absolutely necessary.

---

## Groups

Rather than attaching permissions directly to individual users, you put users into groups and attach permissions to the group. Anyone in the group inherits those permissions automatically.

A simple example: a Developers group with EC2 and S3 access. Add a new developer to the group and they immediately have the right access. Remove them from the group and access is revoked. Much cleaner than managing permissions per user.

---

## Policies

Policies are JSON documents that define what's allowed. There are AWS managed policies (pre-built by AWS, like AmazonEC2FullAccess) and customer managed policies that you write yourself for more specific needs.

The principle I tried to apply throughout is least privilege. Only grant the permissions actually needed for the task. It's tempting early on to just attach AdministratorAccess to everything because it's easier, but that's a bad habit to build.

---

## Access Keys

Access keys are how the CLI and applications authenticate with AWS. There's an Access Key ID (effectively a username) and a Secret Access Key (effectively a password, shown only once at creation).

The main rules I've taken away:

- Never commit access keys to a code repository. Ever. GitHub will sometimes flag this automatically but don't rely on it.
- Delete keys that aren't being used.
- Rotate keys regularly.
- Where possible, use IAM roles rather than access keys (particularly for EC2 instances).

---

## MFA

MFA adds a second layer on top of passwords. I enabled it on both the root account and my IAM user. For anything in a real environment this should be considered mandatory rather than optional.

---

## AWS CLI

The CLI lets you interact with AWS from a terminal instead of the console. Once I'd set up my IAM user and generated access keys, I configured the CLI and started running commands like:

```bash
aws iam list-users
aws ec2 describe-instances
aws s3 ls
```

Getting comfortable with the CLI early matters because most real-world AWS work isn't done by clicking through the console. It's done via CLI, scripts, or Infrastructure as Code.

---

## What I took from this section

IAM isn't just a setup step you do once. It underpins everything in AWS. EC2 uses IAM roles to talk to other services. Lambda has execution roles. RDS supports IAM authentication. Understanding it properly early on means it's not a source of confusion later when it keeps appearing in other services.

The distinction between authentication (proving who you are) and authorisation (what you're allowed to do) is worth being clear on. IAM handles both.
