# 🗳️ E-Voting for Community DAOs

A secure, transparent, and efficient voting system for DAOs built on Stacks blockchain.

## 🎯 Features

- ✨ Single-vote verification
- ⏰ Time-bound voting sessions
- 🔒 Non-transferable voting rights
- 📊 Transparent vote counting
- 🏛️ Member management system

## 🚀 Getting Started

### Prerequisites
- Clarinet
- Stacks wallet

### Contract Functions

#### For Administrators
- `initialize-contract`: Set up the contract
- `add-member`: Add voting members
- `remove-member`: Remove voting members

#### For Members
- `create-proposal`: Create new voting proposals
- `vote`: Cast votes on active proposals
- `get-proposal`: View proposal details
- `get-vote`: Check voting status
- `is-member`: Verify membership
- `get-current-proposal`: View current active proposal

## 📖 Usage Example

1. Initialize contract
2. Add DAO members
3. Create proposal
4. Members cast votes
5. View results

## 🔐 Security

- One vote per member
- Automatic time window enforcement
- Immutable vote recording
```
