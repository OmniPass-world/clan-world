// ILLMClient — abstraction over Elder reasoning backends.
//   - AnthropicClient — direct Claude API (used by Submission 1 Elders)
//   - ZeroGClient     — 0G sealed inference (Submission 2 OpenAgents Track 2 punchline)
//
// Note (per ~/claudes-world policy): Submission 1's Elders run as Claude Code sessions
// spawned by the orchestrator and reason via the Claude OAuth session, not via API
// keys. AnthropicClient here is for non-Elder LLM uses (e.g., the post-tick narrator).
import { readEnv } from './_env';

export interface ILLMClient {
  complete(prompt: string): Promise<string>;
}

class AnthropicClient implements ILLMClient {
  async complete(_prompt: string): Promise<string> {
    throw new Error('AnthropicClient: not implemented (Wave 1+)');
  }
}

class ZeroGClient implements ILLMClient {
  async complete(_prompt: string): Promise<string> {
    throw new Error('ZeroGClient: not implemented (Submission 2)');
  }
}

export function createLLMClient(): ILLMClient {
  return readEnv('CLAN_WORLD_USE_STUB_LLM') === 'true'
    ? new AnthropicClient() // stub flag = use Anthropic; toggle to ZeroG when sealed inference lands
    : new ZeroGClient();
}
