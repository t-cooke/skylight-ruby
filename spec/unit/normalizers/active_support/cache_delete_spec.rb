require "spec_helper"

module Skylight
  describe "Normalizers", "cache_delete.active_support", :agent do

    it "normalizes the notification name with defaults" do
      name, title, desc, payload = normalize(key: "foo")

      name.should == "app.cache.delete"
      title.should == "cache delete"
      desc.should == nil
      payload.should == { key: "foo" }
    end
  end
end
