# Acknowledgments

Mythforge stands on a lot of open-source work. This file credits what the game
actually ships or runs against, and notes the licenses.

If you believe something here is mis-attributed or missing, please open an
issue — it will be corrected promptly.

## The engine and the model runtime

- **[Godot Engine](https://godotengine.org)** — the game engine. Copyright ©
  Juan Linietsky, Ariel Manzur and contributors. **MIT License.**

- **[NobodyWho](https://github.com/nobodywho-ooo/nobodywho)** — the GDExtension
  that runs a language model inside the game: chat, embeddings, reranking and
  speech-to-text. **MIT License.** This is what makes the Game Master, campaign
  memory and voice input local; there is no server behind them.

- **[llama.cpp](https://github.com/ggml-org/llama.cpp)** by Georgi Gerganov and
  contributors — the inference engine underneath NobodyWho, reached here through
  its Vulkan backend. **MIT License.**

- **[stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)** by
  leejet and contributors — the image engine, run as a separate local process
  serving the OpenAI image API on `127.0.0.1:8189`. **MIT License.**

## Models

Downloaded at install time, not redistributed with the game. Each carries its own
license, worth reading if you plan to distribute what you make with it:

| Model | Used for | License |
|---|---|---|
| Meta Llama 3.1 8B Instruct (GGUF) | the narrator | Llama 3.1 Community License |
| nomic-embed-text v1.5 (GGUF) | campaign memory | Apache-2.0 |
| whisper.cpp `ggml-base.en` | voice input | MIT |
| DreamShaper XL Turbo by Lykon | art | CreativeML Open RAIL++-M |

## Python art tooling

`scripts/` holds developer tools for baking world art and fetching the engines —
a player never runs them. They use **requests**/**httpx** (Apache-2.0 /
BSD-3-Clause), **Pillow** (MIT-CMU) and **huggingface_hub** (Apache-2.0).

## History

Mythforge began as a fork of
**[Odysseus](https://github.com/pewdiepie-archdaemon/odysseus)** (Copyright ©
2025 Odysseus Contributors, **MIT License**), a self-hosted AI workspace. None of
that platform still runs — see [NOTICE](NOTICE) — but the license is preserved
because the project's history derives from it.
