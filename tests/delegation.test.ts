import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const admin = accounts.get("deployer")!;
const voter1 = accounts.get("wallet_1")!;
const voter2 = accounts.get("wallet_2")!;
const voter3 = accounts.get("wallet_3")!;

const contractName = "E-Voting-for-Community-DAOs";

describe("Delegation Feature Tests", () => {
  beforeEach(() => {
    simnet.callPublicFn(contractName, "initialize-contract", [], admin);
    simnet.callPublicFn(contractName, "register-voter", [Cl.principal(voter1)], admin);
    simnet.callPublicFn(contractName, "register-voter", [Cl.principal(voter2)], admin);
    simnet.callPublicFn(contractName, "register-voter", [Cl.principal(voter3)], admin);
    simnet.callPublicFn(contractName, "create-proposal", [Cl.stringAscii("Test"), Cl.stringAscii("Test proposal"), Cl.uint(100)], voter1);
  });

  it("should delegate vote successfully", () => {
    const { result } = simnet.callPublicFn(contractName, "delegate-vote", [Cl.uint(1), Cl.principal(voter2)], voter1);
    expect(result).toBeOk(true);
    
    const delegation = simnet.callReadOnlyFn(contractName, "get-delegation", [Cl.principal(voter1), Cl.uint(1)], admin);
    expect(delegation.result).toBeSome();
  });

  it("should prevent delegation to self", () => {
    const { result } = simnet.callPublicFn(contractName, "delegate-vote", [Cl.uint(1), Cl.principal(voter1)], voter1);
    expect(result).toBeErr(Cl.uint(105));
  });

  it("should cast delegated vote with correct power", () => {
    simnet.callPublicFn(contractName, "delegate-vote", [Cl.uint(1), Cl.principal(voter2)], voter1);
    simnet.callPublicFn(contractName, "delegate-vote", [Cl.uint(1), Cl.principal(voter2)], voter3);
    
    const { result } = simnet.callPublicFn(contractName, "cast-delegated-vote", [Cl.uint(1), Cl.bool(true)], voter2);
    expect(result).toBeOk(Cl.uint(3)); // Own vote + 2 delegated
  });

  it("should track delegation power correctly", () => {
    simnet.callPublicFn(contractName, "delegate-vote", [Cl.uint(1), Cl.principal(voter2)], voter1);
    simnet.callPublicFn(contractName, "delegate-vote", [Cl.uint(1), Cl.principal(voter2)], voter3);
    
    const power = simnet.callReadOnlyFn(contractName, "get-delegation-power", [Cl.principal(voter2), Cl.uint(1)], admin);
    expect(power.result).toBeUint(2);
  });

  it("should revoke delegation successfully", () => {
    simnet.callPublicFn(contractName, "delegate-vote", [Cl.uint(1), Cl.principal(voter2)], voter1);
    
    const { result } = simnet.callPublicFn(contractName, "revoke-delegation", [Cl.uint(1)], voter1);
    expect(result).toBeOk(true);
    
    const hasDelegated = simnet.callReadOnlyFn(contractName, "has-delegated", [Cl.principal(voter1), Cl.uint(1)], admin);
    expect(hasDelegated.result).toBeBool(false);
  });
});
