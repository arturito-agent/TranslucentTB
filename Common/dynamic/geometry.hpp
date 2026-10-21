#pragma once
#include <cstdint>
#include <optional>

namespace Dynamic {
	struct Rect {
		std::int32_t left, top, right, bottom;
		constexpr bool operator==(const Rect &) const = default;
	};
	enum class Edge { Left, Right, Bottom };
	struct Geometry { Rect rect; Edge edge; };

	inline std::optional<Geometry> SampleGeometry(Rect monitor, Rect bar) noexcept
	{
		if (monitor.right <= monitor.left || monitor.bottom <= monitor.top ||
			bar.right <= bar.left || bar.bottom <= bar.top ||
			bar.left < monitor.left || bar.right > monitor.right ||
			bar.top < monitor.top || bar.bottom > monitor.bottom) return {};
		Rect rect = monitor;
		Edge edge;
		if (bar.bottom - bar.top > bar.right - bar.left)
		{
			if (bar.left == monitor.left)
			{
				edge = Edge::Left;
				const auto start = static_cast<std::int64_t>(bar.right);
				if (start + 1 > monitor.right) return {};
				rect.left = static_cast<std::int32_t>(start); rect.right = rect.left + 1;
			}
			else if (bar.right == monitor.right)
			{
				edge = Edge::Right;
				const auto end = static_cast<std::int64_t>(bar.left);
				if (end - 1 < monitor.left) return {};
				rect.right = static_cast<std::int32_t>(end); rect.left = rect.right - 1;
			}
			else return {};
		}
		else if (bar.bottom == monitor.bottom)
		{
			edge = Edge::Bottom;
			const auto end = static_cast<std::int64_t>(bar.top);
			if (end - 1 < monitor.top) return {};
			rect.bottom = static_cast<std::int32_t>(end); rect.top = rect.bottom - 1;
		}
		else return {}; // Top taskbars are intentionally out of scope.
		return Geometry{ rect, edge };
	}
}
