module Pkg::Metrics
  module_function

  require "google/apis/sheets_v4"
  require "googleauth"
  require "googleauth/stores/file_token_store"

  OOB_URI = "urn:ietf:wg:oauth:2.0:oob".freeze
  CREDENTIALS_PATH = "credentials.json".freeze
  # The file token.yaml stores the user's access and refresh tokens, and is
  # created automatically when the authorization flow completes for the first
  # time.
  TOKEN_PATH = "token.yaml".freeze
  SCOPE = Google::Apis::SheetsV4::AUTH_SPREADSHEETS

  ##
  # Ensure valid credentials, either by restoring from the saved credentials
  # files or intitiating an OAuth2 authorization. If authorization is required,
  # the user's default browser will be launched to approve the request.
  #
  # @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
  def authorize
    client_id = Google::Auth::ClientId.from_file CREDENTIALS_PATH
    token_store = Google::Auth::Stores::FileTokenStore.new file: TOKEN_PATH
    authorizer = Google::Auth::UserAuthorizer.new client_id, SCOPE, token_store
    user_id = "default"
    credentials = authorizer.get_credentials user_id
    if credentials.nil?
      url = authorizer.get_authorization_url base_url: OOB_URI
      puts "Open the following URL in the browser and enter the " \
           "resulting code after authorization:\n" + url
      code = gets
      credentials = authorizer.get_and_store_credentials_from_code(
        user_id: user_id, code: code, base_url: OOB_URI
      )
    end
    credentials
  end

  def todays_date
    today = Time.now
    return "#{today.month}/#{today.day}/#{today.year}"
  end

  def add_new_row_values(spreadsheet_id, range, values)
    # Initialize the API
    service = Google::Apis::SheetsV4::SheetsService.new
    service.authorization = authorize

    value_range_object = Google::Apis::SheetsV4::ValueRange.new(values: values)
    result = service.append_spreadsheet_value(spreadsheet_id, range, value_range_object, value_input_option: 'USER_ENTERED', insert_data_option: 'INSERT_ROWS', include_values_in_response: true)
  end

  def update_release_spreadsheet
    spreadsheet_id = '1Kvz3lJ_xymk-H4DsyAApOeT6NDjSArH7KYukWegx9-A'
    range = 'Sheet1'
    values = [[todays_date, Pkg::Config.project, Pkg::Config.ref, 'y']]

    add_new_row_values(spreadsheet_id, range, values)
  end
end
