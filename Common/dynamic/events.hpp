#pragma once
#include <optional>
#include <utility>

namespace Dynamic {
	// One read, with at most one confirmation. Duplicate contexts never replenish
	// work; replacing a context keeps the worker's already scheduled deadline.
	template<class Context>
	struct EventSample {
		std::optional<Context> context;
		unsigned remaining = 0;

		bool Request(std::optional<Context> next)
		{
			if (context == next) return false;
			context = std::move(next);
			remaining = context ? 2u : 0u;
			return true;
		}

		void Consumed(bool needsConfirmation) noexcept
		{
			remaining = remaining == 2 && needsConfirmation ? 1u : 0u;
		}
	};
}
