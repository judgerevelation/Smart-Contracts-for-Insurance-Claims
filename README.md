# Smart Contracts for Insurance Claims
A decentralized insurance claims processing system built on Stacks blockchain.

## 🎯 Features

- Submit insurance claims with medical codes
- Automated verification process
- Secure payment processing
- Balance management for patients
- Real-time claim status tracking

## 🚀 Usage

### For Patients

1. Submit a claim:
```clarity
(contract-call? .insurance-claims submit-claim u1000 "MED123")
```

2. Check claim status:
```clarity
(contract-call? .insurance-claims get-claim-details u1)
```

3. Withdraw balance:
```clarity
(contract-call? .insurance-claims withdraw-balance)
```

### For Insurance Providers

1. Verify claim:
```clarity
(contract-call? .insurance-claims verify-claim u1)
```

2. Process payment:
```clarity
(contract-call? .insurance-claims process-payment u1)
```

## 🔒 Security

- Only contract owner can verify claims and process payments
- Double-processing prevention
- Amount validation
- Balance tracking per patient

## 📊 Contract Structure

- Claims stored in `InsuranceClaims` map
- Patient balances tracked in `PatientBalances` map
- Automated status updates
- Built-in error handling

## 🛠 Testing

Use Clarinet to deploy and test the contract:

```bash
clarinet console
```

## 📝 License

MIT
```
