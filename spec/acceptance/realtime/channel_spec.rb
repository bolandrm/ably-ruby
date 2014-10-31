require 'spec_helper'
require 'securerandom'

describe Ably::Realtime::Channel do
  include RSpec::EventMachine

  let(:client) do
    Ably::Realtime::Client.new(api_key: api_key, environment: environment)
  end
  let(:channel_name) { SecureRandom.hex(2) }
  let(:payload) { SecureRandom.hex(4) }
  let(:channel) { client.channel(channel_name) }
  let(:messages) { [] }

  it 'attaches to a channel' do
    run_reactor do
      channel.attach
      channel.on(:attached) do
        expect(channel.state).to eq(:attached)
        stop_reactor
      end
    end
  end

  it 'attaches to a channel with a block' do
    run_reactor do
      channel.attach do
        expect(channel.state).to eq(:attached)
        stop_reactor
      end
    end
  end

  it 'detaches from a channel with a block' do
    run_reactor do
      channel.attach do |chan|
        chan.detach do |detached_chan|
          expect(detached_chan.state).to eq(:detached)
          stop_reactor
        end
      end
    end
  end

  it 'publishes 3 messages once attached' do
    run_reactor do
      channel.attach do
        3.times { channel.publish('event', payload) }
      end
      channel.subscribe do |message|
        messages << message if message.data == payload
        stop_reactor if messages.length == 3
      end
    end

    expect(messages.count).to eql(3)
  end

  it 'publishes 3 messages from queue before attached' do
    run_reactor do
      3.times { channel.publish('event', SecureRandom.hex) }
      channel.subscribe do |message|
        messages << message if message.name == 'event'
        stop_reactor if messages.length == 3
      end
    end

    expect(messages.count).to eql(3)
  end

  it 'publishes 3 messages from queue before attached in a single protocol message' do
    run_reactor do
      3.times { channel.publish('event', SecureRandom.hex) }
      channel.subscribe do |message|
        messages << message if message.name == 'event'
        stop_reactor if messages.length == 3
      end
    end

    # All 3 messages should be batched into a single Protocol Message by the client library
    # message.id = "{protocol_message.id}:{protocol_message_index}"

    # Check that all messages share the same message_serial
    message_id = messages.map { |msg| msg.id.split(':')[0] }
    expect(message_id.uniq.count).to eql(1)

    # Check that all messages use message index 0,1,2
    message_indexes = messages.map { |msg| msg.id.split(':')[1] }
    expect(message_indexes).to include("0", "1", "2")
  end

  it 'subscribes and unsubscribes' do
    run_reactor do
      channel.subscribe('click') do |message|
        messages << message
      end
      channel.attach do
        channel.unsubscribe('click')
        channel.publish('click', 'data')
        EventMachine.add_timer(2) do
          stop_reactor
          expect(messages.length).to eql(0)
        end
      end
    end
  end

  it 'subscribes and unsubscribes from multiple channels' do
    run_reactor do
      click_callback = -> (message) { messages << message }

      channel.subscribe('click', &click_callback)
      channel.subscribe('move', &click_callback)
      channel.subscribe('press', &click_callback)

      channel.attach do
        channel.unsubscribe('click')
        channel.unsubscribe('move', &click_callback)
        channel.unsubscribe('press') { this_callback_is_not_subscribed_so_ignored }

        channel.publish('click', 'data')
        channel.publish('move', 'data')
        channel.publish('press', 'data')

        EventMachine.add_timer(2) do
          stop_reactor
          # Only the press subscribe callback should still be subscribed
          expect(messages.length).to eql(1)
        end
      end
    end
  end

  context 'attach failure' do
    let(:restricted_client) do
      Ably::Realtime::Client.new(api_key: restricted_api_key, environment: environment)
    end
    let(:restricted_channel) { restricted_client.channel("cannot_subscribe") }

    it 'triggers failed event' do
      run_reactor do
        restricted_channel.attach
        restricted_channel.on(:failed) do |error|
          expect(restricted_channel.state).to eq(:failed)
          expect(error.status_code).to eq(401)
          stop_reactor
        end
      end
    end
  end
end


