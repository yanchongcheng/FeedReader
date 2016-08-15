//	This file is part of FeedReader.
//
//	FeedReader is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	FeedReader is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with FeedReader.  If not, see <http://www.gnu.org/licenses/>.

public class FeedReader.OwnCloudNewsMessage : GLib.Object {

    private Soup.Session m_session;
	private Soup.Message m_message_soup;
    private GLib.StringBuilder m_message_string;
	private string m_contenttype;
	private Json.Parser m_parser;
	private Json.Object m_root_object;
    private string m_method;
    private OwncloudNewsUtils m_utils;

    public OwnCloudNewsMessage(string destination, string username, string password, string method)
    {
        m_utils = new OwncloudNewsUtils();
        m_message_string = new GLib.StringBuilder();
        m_method = method;
		m_session = new Soup.Session();
        m_session.ssl_strict = false;
		m_contenttype = "application/json";
		m_parser = new Json.Parser();
		m_message_soup = new Soup.Message(m_method, destination);

        string credentials = username + ":" + password;
        string base64 = GLib.Base64.encode(credentials.data);
        m_message_soup.request_headers.append("Authorization","Basic %s".printf(base64));

        m_session.authenticate.connect((msg, auth, retrying) => {
			if(m_utils.getHtaccessUser() == "")
			{
				logger.print(LogMessage.ERROR, "ownCloud Session: need Authentication");
			}
			else
			{
				auth.authenticate(m_utils.getHtaccessUser(), m_utils.getHtaccessPasswd());
			}
		});
	}

    public void add_int(string type, int val)
	{
		m_message_string.append(",\"" + type + "\":" + val.to_string());
	}

	public void add_int_array(string type, string values)
	{
		m_message_string.append(",\"" + type + "\":[" + values + "]");
	}

	public void add_bool(string type, bool val)
	{
		m_message_string.append(",\"" + type + "\":");
		if(val)
			m_message_string.append("true");
		else
			m_message_string.append("false");
	}

	public void add_string(string type, string val)
	{
		m_message_string.append(",\"" + type + "\":\"" + val + "\"");
	}

    public ConnectionError send(bool ping = false)
	{
        var settingsTweaks = new GLib.Settings("org.gnome.feedreader.tweaks");
        m_message_string.overwrite(0, "{").append("}");
		m_message_soup.set_request(m_contenttype, Soup.MemoryUse.COPY, m_message_string.str.data);

		if(settingsTweaks.get_boolean("do-not-track"))
				m_message_soup.request_headers.append("DNT", "1");

		var status = m_session.send_message(m_message_soup);

        if(status == 401) // unauthorized
		{
			return ConnectionError.UNAUTHORIZED;
		}

        if(m_message_soup.tls_errors != 0 && !settingsTweaks.get_boolean("ignore-tls-errors"))
		{
			logger.print(LogMessage.INFO, "TLS errors: " + Utils.printTlsCertificateFlags(m_message_soup.tls_errors));
			return ConnectionError.CA_ERROR;
		}

		if((string)m_message_soup.response_body.flatten().data == null
		|| (string)m_message_soup.response_body.flatten().data == "")
        {
            logger.print(LogMessage.ERROR, "ownCloud Message: No response - status code: %s".printf(Soup.Status.get_phrase(m_message_soup.status_code)));
            return ConnectionError.NO_RESPONSE;
        }

        if(ping)
        {
            logger.print(LogMessage.DEBUG, "ownCloud Message: ping successfull");
			return ConnectionError.SUCCESS;
        }

		try{
			m_parser.load_from_data((string)m_message_soup.response_body.flatten().data);
		}
		catch (Error e) {
			logger.print(LogMessage.ERROR, "Could not load response from Message to owncloud");
            printMessage();
			logger.print(LogMessage.ERROR, e.message);
			return ConnectionError.UNKNOWN;
		}

		m_root_object = m_parser.get_root().get_object();
		return ConnectionError.SUCCESS;
	}

    public Json.Object? get_response_object()
	{
		return m_root_object;
	}

    public string getMessage()
	{
		return m_message_string.str;
	}

    public void printMessage()
    {
        logger.print(LogMessage.DEBUG, m_message_string.str);
    }

	public void printResponse()
	{
		logger.print(LogMessage.DEBUG, (string)m_message_soup.response_body.flatten().data);
	}
}
