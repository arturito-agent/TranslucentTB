#pragma once
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>
#include "dynamic/analysis.hpp"
#include "dynamic/geometry.hpp"

namespace Dynamic {
	// Experimental comparison backend, selected at build time. Production default
	// remains GDI until the end-to-end measurements justify another choice.
	class DxgiCapture {
		template<class T> using Ptr = Microsoft::WRL::ComPtr<T>;
		Ptr<ID3D11Device> m_Device;
		Ptr<ID3D11DeviceContext> m_Context;
		Ptr<IDXGIOutputDuplication> m_Duplication;
		Ptr<ID3D11Texture2D> m_Staging;
		HMONITOR m_Monitor = nullptr;
		RECT m_Desktop{};
		UINT m_Width = 0, m_Height = 0;
		std::optional<Segment> m_Last;
		std::optional<Rgb> m_LastPrevious;
		std::optional<Geometry> m_LastGeometry;
		HRESULT m_Error = S_OK;

		HRESULT Initialize(HMONITOR monitor) noexcept
		{
			Ptr<IDXGIFactory1> factory;
			HRESULT result = CreateDXGIFactory1(IID_PPV_ARGS(&factory));
			if (FAILED(result)) return result;
			for (UINT a = 0; ; ++a)
			{
				Ptr<IDXGIAdapter1> adapter;
				result = factory->EnumAdapters1(a, &adapter);
				if (result == DXGI_ERROR_NOT_FOUND) return DXGI_ERROR_UNSUPPORTED;
				if (FAILED(result)) return result;
				for (UINT o = 0; ; ++o)
				{
					Ptr<IDXGIOutput> output;
					result = adapter->EnumOutputs(o, &output);
					if (result == DXGI_ERROR_NOT_FOUND) break;
					if (FAILED(result)) return result;
					DXGI_OUTPUT_DESC desc{};
					result = output->GetDesc(&desc);
					if (FAILED(result)) return result;
					if (desc.Monitor != monitor) continue;
					if (desc.Rotation != DXGI_MODE_ROTATION_IDENTITY) return E_NOTIMPL;
					result = D3D11CreateDevice(adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
						D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
						&m_Device, nullptr, &m_Context);
					if (FAILED(result)) return result;
					Ptr<IDXGIOutput1> output1;
					result = output.As(&output1);
					if (FAILED(result)) return result;
					result = output1->DuplicateOutput(m_Device.Get(), &m_Duplication);
					if (FAILED(result)) return result;
					m_Monitor = monitor; m_Desktop = desc.DesktopCoordinates;
					return S_OK;
				}
			}
		}

	public:
		void Reset() noexcept
		{
			m_Staging.Reset(); m_Duplication.Reset(); m_Context.Reset(); m_Device.Reset();
			m_Monitor = nullptr; m_Width = m_Height = 0;
			m_Last.reset(); m_LastPrevious.reset(); m_LastGeometry.reset();
		}
		HRESULT LastError() const noexcept { return m_Error; }

		std::optional<Segment> Capture(Geometry geometry, std::optional<Rgb> previous) noexcept
		{
			const auto r = geometry.rect;
			RECT region{ r.left, r.top, r.right, r.bottom };
			const auto monitor = MonitorFromRect(&region, MONITOR_DEFAULTTONULL);
			if (!monitor) { m_Error = E_INVALIDARG; return {}; }
			if (monitor != m_Monitor)
			{
				Reset();
				m_Error = Initialize(monitor);
				if (FAILED(m_Error)) { Reset(); return {}; }
			}
			DXGI_OUTDUPL_FRAME_INFO info{};
			Ptr<IDXGIResource> resource;
			m_Error = m_Duplication->AcquireNextFrame(16, &info, &resource);
			if (m_Error == DXGI_ERROR_WAIT_TIMEOUT)
			{
				// Reuse only a result from the identical geometry AND tie-break state.
				if (m_LastGeometry && m_LastGeometry->rect == r && m_LastGeometry->edge == geometry.edge &&
					m_LastPrevious == previous) return m_Last;
				return {};
			}
			if (FAILED(m_Error)) { Reset(); return {}; }
			struct Frame { IDXGIOutputDuplication *duplication; ~Frame() { duplication->ReleaseFrame(); } } frame{ m_Duplication.Get() };
			Ptr<ID3D11Texture2D> texture;
			m_Error = resource.As(&texture);
			if (FAILED(m_Error)) return {};
			const auto width = static_cast<UINT>(r.right - r.left);
			const auto height = static_cast<UINT>(r.bottom - r.top);
			if (r.left < m_Desktop.left || r.top < m_Desktop.top ||
				r.right > m_Desktop.right || r.bottom > m_Desktop.bottom) { m_Error = E_INVALIDARG; return {}; }
			if (width != m_Width || height != m_Height)
			{
				m_Staging.Reset();
				D3D11_TEXTURE2D_DESC desc{};
				desc.Width = width; desc.Height = height; desc.MipLevels = 1; desc.ArraySize = 1;
				desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM; desc.SampleDesc.Count = 1;
				desc.Usage = D3D11_USAGE_STAGING; desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
				m_Error = m_Device->CreateTexture2D(&desc, nullptr, &m_Staging);
				if (FAILED(m_Error)) return {};
				m_Width = width; m_Height = height;
			}
			const D3D11_BOX box{ static_cast<UINT>(r.left - m_Desktop.left),
				static_cast<UINT>(r.top - m_Desktop.top), 0, static_cast<UINT>(r.right - m_Desktop.left),
				static_cast<UINT>(r.bottom - m_Desktop.top), 1 };
			m_Context->CopySubresourceRegion(m_Staging.Get(), 0, 0, 0, 0, texture.Get(), 0, &box);
			D3D11_MAPPED_SUBRESOURCE mapped{};
			m_Error = m_Context->Map(m_Staging.Get(), 0, D3D11_MAP_READ, 0, &mapped);
			if (FAILED(m_Error)) return {};
			m_Last = Analyze({ {static_cast<const std::uint8_t *>(mapped.pData),
				static_cast<std::size_t>(mapped.RowPitch) * height}, width, height, mapped.RowPitch,
				geometry.edge != Edge::Bottom }, previous);
			m_Context->Unmap(m_Staging.Get(), 0);
			m_LastPrevious = previous; m_LastGeometry = geometry;
			return m_Last;
		}
	};
}
