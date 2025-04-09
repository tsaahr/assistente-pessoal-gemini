require 'capybara'
require 'capybara/dsl'
require 'webdrivers'
require 'selenium-webdriver'
require 'net/http'
require 'json'
require 'dotenv/load'

class GeminiBot
  include Capybara::DSL

  GEMINI_API_KEY = ENV['GEMINI_API_KEY']

  def initialize
    user_data_dir = "/home/lithierry/.config/gemini-bot-profile"

    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument("--user-data-dir=#{user_data_dir}")
    options.add_argument("--start-maximized")

    Capybara.register_driver :selenium_chrome do |app|
      Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
    end

    Capybara.default_driver = :selenium_chrome
    Capybara.default_max_wait_time = 10

    visit('https://web.whatsapp.com/')
    puts "[INFO] Aguardando login manual no WhatsApp..."
    sleep(10)

    find('span', text: 'Twilio', match: :first).click
    puts "[INFO] Conversa selecionada."
    sleep(5)

    @last_replied_message = nil
    listen_loop
  end

  private

  def listen_loop
    loop do
      begin
        read_and_answer_last_message
      rescue => e
        puts "[ERRO] #{e.message}"
      end
      sleep(30)
    end
  end

  def read_and_answer_last_message
    received_messages = all('div.message-in span.selectable-text').map(&:text).last(10)

    if received_messages.empty?
      puts "[INFO] Nenhuma mensagem recebida encontrada."
      return
    end

    last_message = received_messages.last

    if last_message == @last_replied_message
      puts "[INFO] Nenhuma nova mensagem. Aguardando..."
      return
    end

    puts "[INFO] Nova mensagem detectada: #{last_message}"
    @last_replied_message = last_message

    context = <<~CONTEXT
      Imagine que você está respondendo mensagens de um cliente, amigo ou colega de trabalho.
      Baseado nas últimas mensagens, gere uma resposta empática, direta e clara, como se fosse um assistente pessoal que entende o tom da conversa.
      As últimas mensagens dele foram:
      #{received_messages.join("\n")}
    CONTEXT

    gemini_response = fetch_gemini_response(context)

    if gemini_response.nil? || gemini_response.strip.empty?
      puts "[ERRO] A resposta da API veio vazia."
      return
    end

    puts "[INFO] Resposta gerada: #{gemini_response}"

    message_input = find('div[aria-placeholder="Digite uma mensagem"]')
    sleep(20)
    message_input.send_keys(gemini_response)
    message_input.send_keys(:enter)

    puts "[INFO] Resposta enviada com sucesso."
  end

  def fetch_gemini_response(context)
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=#{GEMINI_API_KEY}")
    headers = { 'Content-Type': 'application/json' }

    body = {
      contents: [
        {
          parts: [
            { text: context }
          ]
        }
      ]
    }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri, headers)
    request.body = body

    response = http.request(request)
    json_response = JSON.parse(response.body)
  
    json_response.dig("candidates", 0, "content", "parts", 0, "text")
  end
end

GeminiBot.new
