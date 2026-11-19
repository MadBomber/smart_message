#!/usr/bin/env ruby
# examples/memory/05_many_to_many_chat.rb
# frozen_string_literal: true
#
# Many-to-many messaging: a chat system
#
# Several agents publish and subscribe to the same message classes.  Each
# agent subscribes with its own block, keeps only the rooms it has joined,
# and can leave by unsubscribing its handler.  A bot listens for commands
# and answers in the room.

require_relative '../support/example_helper'
require_relative 'messages/chat_message'
require_relative 'messages/bot_command_message'
require_relative 'messages/system_notification_message'

TRANSPORT = SmartMessage::Transport::MemoryTransport.new
[ChatMessage, BotCommandMessage, SystemNotificationMessage].each { it.transport(TRANSPORT) }

# A person in one or more rooms.
class ChatAgent
  attr_reader :name

  def initialize(name)
    @name  = name
    @rooms = Concurrent::Set.new
  end

  # Start listening; returns the handler id needed to stop again.
  def connect
    @handler_id = ChatMessage.subscribe { |message| receive(message) }
  end

  def disconnect = ChatMessage.unsubscribe(@handler_id)

  def join(room_id)
    @rooms << room_id
    SystemNotificationMessage.new(room_id: room_id, notification_type: 'user_joined', content: "#{name} joined").publish
  end

  def say(room_id, content)
    if content.start_with?('/')
      command, *arguments = content.delete_prefix('/').split
      BotCommandMessage.new(room_id: room_id, command: command, arguments: arguments, from: name).publish
    else
      ChatMessage.new(room_id: room_id, sender_name: name, content: content, from: name).publish
    end
  end

  def receive(message)
    return unless @rooms.include?(message.room_id) && message.sender_name != name

    Example.inbox.add(name, "#{message.room_id}/#{message.sender_name}: #{message.content}")
  end
end

# Answers "/echo words" in the room the command came from.
module EchoBot
  def self.handle_command(command)
    return unless command.command == 'echo'

    ChatMessage.new(
      room_id: command.room_id, sender_name: 'EchoBot', content: command.arguments.join(' '), from: 'echo-bot'
    ).publish
  end
end

Example.title 'Many-to-many chat'
SystemNotificationMessage.subscribe { |notice| Example.inbox.add(:notices, notice.content) }
BotCommandMessage.subscribe('EchoBot.handle_command')

alice, bob, carol = %w[Alice Bob Carol].map { ChatAgent.new(it) }
[alice, bob, carol].each(&:connect)
alice.join('general')
bob.join('general')
bob.join('tech')
carol.join('tech')

alice.say('general', 'Hello everyone')
carol.say('tech', 'Anyone tried Ruby 4?')
bob.say('tech', '/echo yes we have')
Example.wait_for_idle(TRANSPORT)

Example.section 'What each agent saw'
[alice, bob, carol].each { |agent| puts "  #{agent.name}: #{Example.inbox[agent.name].sort}" }

Example.check('four join notices were broadcast') { Example.inbox.count(:notices) == 4 }
Example.check('Bob (in both rooms) saw Alice, Carol and the bot') do
  Example.inbox[bob.name].sort == ['general/Alice: Hello everyone', 'tech/Carol: Anyone tried Ruby 4?', 'tech/EchoBot: yes we have']
end
Example.check('Alice saw nothing from the tech room') { Example.inbox[alice.name].empty? }
Example.check('Carol saw the bot answer in tech and nothing from general') do
  Example.inbox[carol.name] == ['tech/EchoBot: yes we have']
end

Example.section 'Leaving: an unsubscribed agent receives nothing more'
bob.disconnect
alice.say('general', 'Bob, are you still there?')
Example.wait_for_idle(TRANSPORT)
Example.check('Bob received nothing after disconnecting') { Example.inbox.count(bob.name) == 3 }
Example.check('two chat handlers remain subscribed') { TRANSPORT.subscribers['ChatMessage'].size == 2 }

Example.finish
