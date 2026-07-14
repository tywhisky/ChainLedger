"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";

type Network = {
  id: string;
  name: string;
  chain_id: number;
  native_symbol: string;
  is_testnet: boolean;
};

type Workspace = {
  id: string;
  name: string;
  network: Network;
  created_at: string;
};

type ApiResponse<T> = {
  data: T;
  error?: { message?: string };
};

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, init);
  const body = (await response.json()) as ApiResponse<T>;
  if (!response.ok) {
    throw new Error(body.error?.message ?? "The request could not be completed.");
  }
  return body.data;
}

export default function Home() {
  const [networks, setNetworks] = useState<Network[]>([]);
  const [selectedNetwork, setSelectedNetwork] = useState("");
  const [name, setName] = useState("");
  const [created, setCreated] = useState<Workspace | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const loadNetworks = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const available = await request<Network[]>("/v1/networks");
      setNetworks(available);
      setSelectedNetwork((current) => current || available[0]?.id || "");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Unable to load networks.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadNetworks();
  }, [loadNetworks]);

  async function createWorkspace(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSubmitting(true);
    setError("");
    setCreated(null);
    try {
      const workspace = await request<Workspace>("/v1/workspaces", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, network_id: selectedNetwork }),
      });
      setCreated(workspace);
      setName("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Unable to create workspace.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="app-shell">
      <header className="site-header">
        <a className="brand" href="#top" aria-label="ChainLedger home">
          <span className="brand-mark">CL</span>
          <span>ChainLedger</span>
        </a>
        <div className="environment"><span /> Testnet environment</div>
      </header>

      <section className="hero" id="top">
        <div className="intro">
          <p className="eyebrow">Workspace setup · Step 01</p>
          <h1>Give your on-chain operations a clear boundary.</h1>
          <p className="lead">
            A workspace is your private operating area inside ChainLedger. It groups the network,
            watched addresses, webhooks, members, and activity that belong together.
          </p>

          <div className="boundary-card">
            <p className="boundary-label">System boundary</p>
            <div className="boundary-row">
              <span className="boundary-number">01</span>
              <div><strong>Workspace</strong><span>Lives in ChainLedger</span></div>
            </div>
            <div className="boundary-line" />
            <div className="boundary-row">
              <span className="boundary-number">02</span>
              <div><strong>EVM network</strong><span>Defines where chain data comes from</span></div>
            </div>
          </div>
        </div>

        <div className="setup-card">
          <div className="card-heading">
            <div>
              <p className="step-label">Create workspace</p>
              <h2>Start with the essentials</h2>
            </div>
            <span className="step-count">1 / 1</span>
          </div>

          <form onSubmit={createWorkspace}>
            <label htmlFor="workspace-name">Workspace name</label>
            <input
              id="workspace-name"
              name="workspace-name"
              type="text"
              maxLength={100}
              placeholder="e.g. Treasury monitoring"
              value={name}
              onChange={(event) => setName(event.target.value)}
              required
            />
            <p className="field-hint">Use a name your team will recognize.</p>

            <fieldset>
              <legend>EVM network</legend>
              {loading ? (
                <div className="network-placeholder">Loading supported networks…</div>
              ) : networks.length > 0 ? (
                <div className="network-list">
                  {networks.map((network) => (
                    <label className="network-option" key={network.id}>
                      <input
                        type="radio"
                        name="network"
                        value={network.id}
                        checked={selectedNetwork === network.id}
                        onChange={() => setSelectedNetwork(network.id)}
                      />
                      <span className="network-symbol">{network.native_symbol}</span>
                      <span className="network-copy">
                        <strong>{network.name}</strong>
                        <small>Chain ID {network.chain_id} · {network.is_testnet ? "Testnet" : "Mainnet"}</small>
                      </span>
                      <span className="radio-mark" aria-hidden="true" />
                    </label>
                  ))}
                </div>
              ) : (
                <button className="retry-button" type="button" onClick={() => void loadNetworks()}>
                  Retry loading networks
                </button>
              )}
            </fieldset>

            {error && <p className="error-message" role="alert">{error}</p>}

            <button
              className="primary-button"
              type="submit"
              disabled={loading || submitting || !selectedNetwork || name.trim() === ""}
            >
              {submitting ? "Creating workspace…" : "Create workspace"}
              <span aria-hidden="true">→</span>
            </button>
          </form>

          <p className="security-note">Nothing in this step is written on-chain or touches a private key.</p>
        </div>
      </section>

      <section className={`result-panel ${created ? "is-visible" : ""}`} aria-live="polite">
        {created && (
          <>
            <div className="success-mark">✓</div>
            <div className="result-copy">
              <p>Workspace ready</p>
              <h2>{created.name}</h2>
              <span>{created.network.name} · Chain ID {created.network.chain_id}</span>
            </div>
            <div className="workspace-id">
              <span>Workspace ID</span>
              <code>{created.id}</code>
            </div>
          </>
        )}
      </section>
    </main>
  );
}
