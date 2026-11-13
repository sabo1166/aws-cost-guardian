# 💰 AWS Cost Guardian

A small safety net for AWS lab accounts. When monthly spend crosses a budget, it emails you. When it crosses the action threshold, a Lambda function **stops** every running EC2 instance that you opted in with the tag `AutoStop=true`.

I built it before deploying my EKS lab, because EKS, NAT Gateways and worker nodes keep charging even when nothing is running.

## 🏗️ Architecture

```
                      ┌──────────────────────────┐
                      │   AWS Budget ($10/month) │
                      └────────────┬─────────────┘
          50% / 80% actual         │        100% actual or forecasted
        ┌──────────────────────────┴───────────────────────────┐
        ▼                                                      ▼
┌───────────────────┐                               ┌───────────────────┐
│ SNS: warning topic│                               │ SNS: action topic │
└────────┬──────────┘                               └────┬─────────┬────┘
         ▼                                               ▼         ▼
      📧 Email                                       📧 Email   ⚡ Lambda (Python)
                                                                   │
                                     ec2:StopInstances only if tag AutoStop=true
                                                                   ▼
                                                     🖥️ Tagged EC2 instances → stopped
                                                                   │
                                                                   ▼
                                                     📊 CloudWatch Logs (proof)
```

| Component | Why it's there |
| --- | --- |
| **AWS Budgets** | Watches actual and forecasted monthly cost |
| **Two SNS topics** | Early warnings (50%, 80%) only email you. Only the action topic can stop anything. |
| **Lambda (Python 3.12)** | Finds running instances tagged `AutoStop=true` and stops them |
| **Least-privilege IAM** | The Lambda can describe all instances but can **stop only tagged ones**, enforced by an IAM condition on `aws:ResourceTag/AutoStop` |
| **CloudWatch Logs** | Every alert and every action is logged, kept 14 days |
| **Terraform** | All of the above is code |

## 🔐 Safety rules

- **Opt-in only.** Instances without `AutoStop=true` are never touched, even if the Lambda code had a bug, because IAM denies it.
- **Stop, never terminate.** EBS volumes and data are kept. Start the instance again any time.
- **Dry-run mode.** Set `dry_run = true` to log what would happen without stopping anything.

## 🚀 Deploy with GitHub Actions (how I run it)

The workflow `.github/workflows/deploy.yml` is started manually (**Actions → Cost Guardian → Run workflow**) and reads the AWS credentials from repository secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`).

| Action | What it does |
| --- | --- |
| `plan` | Creates the encrypted, versioned state bucket on first run, then `terraform plan` |
| `apply` | Plans and applies |
| `test` | Launches a tagged and an untagged `t3.micro`, sends a test alert, checks that **only** the tagged one stops, prints the Lambda logs, then terminates both |
| `destroy` | Removes everything Terraform created (the state bucket is kept) |

Terraform state lives in `cost-guardian-tfstate-<account-id>-<region>` with native S3 locking (`use_lockfile = true`), no DynamoDB table.

## ⚠️ Honest limitations

- **Not real-time.** AWS Budgets evaluates cost data only a few times a day, so the action can come hours after the threshold is crossed. This is a safety net, not a hard spending cap.
- **EC2 only.** It doesn't stop EKS control planes, NAT Gateways, RDS or load balancers. Those still need `terraform destroy`.
- **One region.** The Lambda stops instances in `aws_region` only.
- **Forecast alerts can fire early.** The 100% forecasted alert can trigger before you actually spend $10. That is intended for a lab account.
- **Long-lived IAM access keys in GitHub secrets.** Moving the workflow to GitHub OIDC is next.

## 📌 Status

| Check | Result |
| --- | --- |
| Code committed | ✅ |
| First apply in GitHub Actions | ❌ failed: AWS rejected the access key in repository secrets (`The security token included in the request is invalid`). Fixing the secret. |
| Deployed to AWS | ⏳ |
| Email subscriptions confirmed | ⏳ |
| Tagged instance stopped by test alert | ⏳ |
| Untagged instance left running | ⏳ |

## 💲 Cost

Lambda, SNS and CloudWatch Logs usage here is tiny and normally within the AWS Free Tier. Check [AWS Budgets pricing](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/) for your account. The two `t3.micro` test instances run for a few minutes during `test` and are terminated automatically.

## 👨‍💻 Author

**Mohammed Gamal Al Jaafari** · Cloud & DevOps · [GitHub](https://github.com/sabo1166)
