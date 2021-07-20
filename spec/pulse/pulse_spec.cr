require "./helper"
require "webmock"

# describe PlaceOS::Core::Pulse, focus: true do
#   it "should run tests" do
#     true.should eq true
#     puts "it worked"
#   end
# end

# alias Pulse = PlaceOS::Core::Pulse

describe PlaceOS::Core::Pulse do
  
  it ".new" do
    pulse = PlaceOS::Core::Pulse.new("01EY4PBEN5F999VQKP55V4C3WD", "b18e1d0045995ec3d010c387ccfeb984d783af8fbb0f40fa7db126d889f6dadd77f48b59caeda77751ed138b0ec667ff50f8768c25d48309a8f386a2bad187fb")
    # pulse.instance_id.should eq "01EY4PBEN5F999VQKP55V4C3WD"
    # pulse.secret_key.should eq "b18e1d0045995ec3d010c387ccfeb984d783af8fbb0f40fa7db126d889f6dadd77f48b59caeda77751ed138b0ec667ff50f8768c25d48309a8f386a2bad187fb"
  end

  it ".heartbeat" do
    WebMock.stub(:post, "http://placeos.run/instances/01EY4PBEN5F999VQKP55V4C3WD")
      .to_return(status: 201, body: "")

    pulse = PlaceOS::Core::Pulse.new("01EY4PBEN5F999VQKP55V4C3WD", "b18e1d0045995ec3d010c387ccfeb984d783af8fbb0f40fa7db126d889f6dadd77f48b59caeda77751ed138b0ec667ff50f8768c25d48309a8f386a2bad187fb")
    heartbeat = pulse.heartbeat
    heartbeat.should be_a HTTP::Client::Response
    heartbeat.status_code.should eq 201
  end

  describe Message do
    it ".new" do
      secret = Sodium::Sign::SecretKey.new("b18e1d0045995ec3d010c387ccfeb984d783af8fbb0f40fa7db126d889f6dadd77f48b59caeda77751ed138b0ec667ff50f8768c25d48309a8f386a2bad187fb".hexbytes)
      message = Message.new("01EY4PBEN5F999VQKP55V4C3WD", secret)
      message.instance_id.should eq "01EY4PBEN5F999VQKP55V4C3WD"
      message.portal_uri.should eq URI.parse "http://placeos.run"
      message.signature.should eq "7c51c1bf33cec94259a53f6a5d72420af6d83be0dc16824cf0739df1c844c6c3554597f8ca8739e018bd31c1ba4652215572fcd7ac33ea6d72c0167bd7ab1b0f"
  
      secret.public_key.verify_detached(message.contents.to_json, message.signature.hexbytes).should be_nil
    end
  
    it ".payload" do
      secret = Sodium::Sign::SecretKey.new("b18e1d0045995ec3d010c387ccfeb984d783af8fbb0f40fa7db126d889f6dadd77f48b59caeda77751ed138b0ec667ff50f8768c25d48309a8f386a2bad187fb".hexbytes)
      message = Message.new("01EY4PBEN5F999VQKP55V4C3WD", secret)
      message.payload.should eq "{\"instance_id\":\"01EY4PBEN5F999VQKP55V4C3WD\",\"contents\":{\"drivers_qty\":0,\"zones_qty\":0,\"users_qty\":0,\"staff_api\":true,\"instance_type\":\"PROD\"},\"signature\":\"7c51c1bf33cec94259a53f6a5d72420af6d83be0dc16824cf0739df1c844c6c3554597f8ca8739e018bd31c1ba4652215572fcd7ac33ea6d72c0167bd7ab1b0f\"}"
    end
  
    it ".send" do
      secret = Sodium::Sign::SecretKey.new("b18e1d0045995ec3d010c387ccfeb984d783af8fbb0f40fa7db126d889f6dadd77f48b59caeda77751ed138b0ec667ff50f8768c25d48309a8f386a2bad187fb".hexbytes)
      WebMock.stub(:post, "http://placeos.run/instances/01EY4PBEN5F999VQKP55V4C3WD")
        .to_return(status: 201, body: "")
  
      # heartbeat = Pulse::Heartbeat.new
      Pulse::Heartbeat.new
      message = Message.new("01EY4PBEN5F999VQKP55V4C3WD", secret)
      response = message.send
      response.should be_a HTTP::Client::Response
      response.status_code.should eq 201
    end
  end

end

