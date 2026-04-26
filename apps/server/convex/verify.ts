import { httpAction } from './_generated/server';

export const verifyWorldId = httpAction(async (_ctx, request) => {
  const proof = await request.json() as Record<string, unknown>;

  const appId = process.env.WORLD_APP_ID ?? 'app_9241a337b4c7b008504cea27f238380a';
  const action = process.env.WORLD_ACTION_ID ?? 'clan-join';

  const res = await fetch(`https://developer.worldcoin.org/api/v2/verify/${appId}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ...proof, action, signal: '' }),
  });

  if (!res.ok) {
    return new Response(JSON.stringify({ error: 'verification failed' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
