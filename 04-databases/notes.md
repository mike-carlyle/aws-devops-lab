# Databases: RDS, Aurora, ElastiCache

## RDS: Relational Database Service

RDS is AWS's managed database service. Rather than running a database on an EC2 instance yourself, AWS handles the heavy lifting of keeping it running, patched, and backed up. It supports PostgreSQL, MySQL, MariaDB, Oracle, Microsoft SQL Server, IBM Db2, and Aurora.

### Why use RDS over running a database on EC2

The managed nature of RDS is the main reason. Things you get for free that you'd have to handle yourself on EC2:

- Automatic OS patching
- Continuous backups with point-in-time restore down to a specific timestamp
- Monitoring dashboards built in
- Read replicas for scaling reads
- Multi-AZ for disaster recovery
- Vertical and horizontal scaling options
- Automatic storage scaling for unpredictable loads

The one trade-off is that you cannot SSH into an RDS instance. It's a managed service so AWS controls the underlying infrastructure.

### Storage Auto Scaling

RDS can automatically scale storage when it detects you're running low. This removes the need to manually increase storage and is particularly useful for workloads where usage is hard to predict. You can set a maximum storage threshold to prevent it scaling beyond what you're willing to pay for.

---

## Read Replicas

Read replicas allow you to scale read performance by creating up to 15 copies of your database that handle read traffic. They can be within the same AZ, across AZs, or across regions entirely.

Replication uses an asynchronous method, meaning replicas will eventually be in sync with the primary but there's a window where they might serve slightly stale data if replication hasn't caught up yet. This is worth being aware of for any application where data freshness is critical.

Replicas can also be promoted to become their own standalone database if needed.

### A practical use case

A production database is handling normal application load fine. A reporting team then wants to run analytics queries against it. Running heavy analytics on the production database risks overloading it and impacting real users. The solution is to point the reporting application at a read replica instead, keeping the load off the primary database entirely.

### Cost

Data transfer between AZs in AWS normally incurs a cost. This does not apply to RDS replication within the same region, even across AZs, because it's a managed service. Cross-region replicas do incur a replication fee for the network traffic involved.

---

## Multi-AZ (Disaster Recovery)

Multi-AZ creates a standby copy of your database in a different AZ. Unlike read replicas, this uses synchronous replication, meaning the standby is always up to date. AWS provides a single DNS name for the database and automatically fails over to the standby if the primary goes down, with no manual intervention needed.

Important distinction: Multi-AZ is for availability and disaster recovery only. It is not used for scaling reads. The standby cannot serve traffic under normal circumstances.

### Moving from single to Multi-AZ

This can be done with zero downtime. You simply modify the database and enable Multi-AZ. Behind the scenes AWS takes a snapshot of the primary, restores it into the new AZ, and then establishes synchronisation between the two until they're in sync.

---

## RDS Custom

RDS Custom covers Oracle and Microsoft SQL Server specifically and gives you more control than standard RDS. You can configure settings, install patches, and enable native database features that standard RDS doesn't expose. To do this you deactivate automation mode, but this comes with risk. The course recommendation is to take a snapshot before making any changes so you have a safe restore point.

---

## Hands-on Lab

Created a MySQL RDS instance via the AWS console and set up a new security group with an inbound rule allowing access on port 3306.

Rather than SQLElectron as suggested in the course, I connected using DBeaver which I already had installed. The connection worked first time.

![RDS instance showing as Available in the AWS console](screenshots/rds-instance-available.png)

Once connected I created a new database called Mikes_Database, added a table called Mikes_Table with first_name and last_name columns, and inserted a row of data.

![DBeaver connected to RDS showing Mikes_Database and Mikes_Table](screenshots/dbeaver-connected.png)

![Mikes_Table data showing inserted row](screenshots/mikes-table-data.png)

The RDS monitoring dashboard shows CloudWatch metrics updating in real time including CPU usage, BurstBalance, and BinLogDiskUsage, confirming the instance is active and being monitored automatically.

![RDS monitoring dashboard showing CloudWatch metrics](screenshots/rds-monitoring.png)

---

## What I took from this section

The distinction between read replicas and Multi-AZ is one of the most commonly tested concepts in the SAA exam. Read replicas are for performance and scaling reads. Multi-AZ is for availability and failover. They serve completely different purposes and can be used together.

The async vs sync replication difference matters in practice. Async means replicas might lag behind. Sync means the standby is always current but introduces a small write latency because AWS has to confirm both copies are written before acknowledging success.

The fact that you can't SSH into RDS is a reminder that managed services involve giving up some control in exchange for operational simplicity. For most use cases that's a good trade.
