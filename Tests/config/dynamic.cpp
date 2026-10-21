#include <gtest/gtest.h>
#include <rapidjson/stringbuffer.h>
#include <rapidjson/writer.h>
#include "config/taskbarappearance.hpp"
#include "config/activeinactivetaskbarappearance.hpp"

TEST(DynamicAppearance, JsonAndWinrtRoundTrip)
{
	rj::GenericDocument<rj::UTF16LE<>> document;
	document.Parse(L"{\"accent\":\"dynamic\",\"color\":\"#123456FF\"}");
	ASSERT_FALSE(document.HasParseError());
	TaskbarAppearance appearance;
	appearance.Deserialize(document, nullptr);
	EXPECT_EQ(appearance.Accent, AppearanceAccent::Dynamic);
	const txmp::TaskbarAppearance model = appearance;
	EXPECT_EQ(model.Accent(), txmp::AccentState::Dynamic);
	EXPECT_EQ(TaskbarAppearance(model).Accent, AppearanceAccent::Dynamic);
	rj::GenericStringBuffer<rj::UTF16LE<>> buffer;
	rj::Writer<decltype(buffer), rj::UTF16LE<>, rj::UTF16LE<>> writer(buffer);
	writer.StartObject(); appearance.Serialize(writer); writer.EndObject();
	document.Parse(buffer.GetString());
	ASSERT_FALSE(document.HasParseError());
	TaskbarAppearance restored;
	restored.Deserialize(document, nullptr);
	EXPECT_EQ(restored.Accent, AppearanceAccent::Dynamic);
	EXPECT_EQ(restored.Color.ToRGBA(), appearance.Color.ToRGBA());
}

TEST(DynamicAppearance, LegacyAndInactiveRules)
{
	rj::GenericDocument<rj::UTF16LE<>> document;
	document.Parse(L"{\"accent\":\"clear\",\"inactive\":{\"accent\":\"dynamic\"}}");
	ActiveInactiveTaskbarAppearance rule;
	rule.Deserialize(document, nullptr);
	EXPECT_EQ(rule.Accent, AppearanceAccent::Clear);
	ASSERT_TRUE(rule.Inactive);
	EXPECT_EQ(rule.Inactive->Accent, AppearanceAccent::Dynamic);
}
