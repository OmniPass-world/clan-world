import { httpAction, internalMutation, internalQuery } from './_generated/server';
import { internal } from './_generated/api';
import { v } from 'convex/values';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Content-Type': 'application/json',
};

export const isNullifierVerified = internalQuery({
  args: { nullifier: v.string() },
  handler: async (ctx, { nullifier }) => {
    const existing = await ctx.db
      .query('verifiedNullifiers')
      .withIndex('by_nullifier', (q) => q.eq('nullifier', nullifier))
      .first();
    return existing !== null;
  },
});

export const insertNullifier = internalMutation({
  args: { nullifier: v.string() },
  handler: async (ctx, { nullifier }) => {
    await ctx.db.insert('verifiedNullifiers', { nullifier });
  },
});

export const verifyWorldId = httpAction(async (ctx, request) => {
  const appId = process.env.WORLD_APP_ID;
  if (!appId) throw new Error('WORLD_APP_ID not set in Convex environment');

  const action = process.env.WORLD_ACTION_ID ?? 'clan-join';

  const proof = await request.json() as {
    nullifier_hash?: string;
    merkle_root?: string;
    proof?: string;
    verification_level?: string;
  };

  const { nullifier_hash, merkle_root, proof: proofStr, verification_level } = proof;

  if (!nullifier_hash || !merkle_root || !proofStr) {
    return new Response(JSON.stringify({ error: 'missing proof fields' }), {
      status: 400,
      headers: corsHeaders,
    });
  }

  // Idempotency: return success without re-verifying if already stored
  const alreadyVerified = await ctx.runQuery(internal.verify.isNullifierVerified, {
    nullifier: nullifier_hash,
  });
  if (alreadyVerified) {
    return new Response(JSON.stringify({ success: true, cached: true }), {
      status: 200,
      headers: corsHeaders,
    });
  }

  const res = await fetch(`https://developer.worldcoin.org/api/v2/verify/${appId}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      nullifier_hash,
      merkle_root,
      proof: proofStr,
      verification_level: verification_level ?? 'orb',
      action,
      signal: '',
    }),
  });

  if (!res.ok) {
    const errBody = await res.text().catch(() => '');
    return new Response(JSON.stringify({ error: 'verification failed', detail: errBody }), {
      status: 400,
      headers: corsHeaders,
    });
  }

  // Persist nullifier to prevent replay attacks
  await ctx.runMutation(internal.verify.insertNullifier, { nullifier: nullifier_hash });

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: corsHeaders,
  });
});
