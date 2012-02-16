package MojoX::Transaction::WebSocket76;

use Mojo::Util ('md5_bytes');

use Mojo::Base 'Mojo::Transaction::WebSocket';


our $VERSION = '0.01';


use constant DEBUG => &Mojo::Transaction::WebSocket::DEBUG;

use constant {
	TEXT   => &Mojo::Transaction::WebSocket::TEXT,
	BINARY => &Mojo::Transaction::WebSocket::BINARY,
	CLOSE  => &Mojo::Transaction::WebSocket::CLOSE,
};


sub build_frame {
	my ($self, undef, $type, $bytes) = @_;

	warn("BUILDING FRAME\n") if DEBUG;

	my $length = length($bytes);

	if (DEBUG) {
		warn('TYPE: ', $type, "\n");
		warn('LENGTH: ', $length, "\n");
		if ($length) {
			warn('BYTES: ', $bytes, "\n");
		}
		else {
			warn("NOTHING\n") 
		}
	}

	return "\xff" if $type == CLOSE;
	return "\x00" . $bytes . "\xff";
}

sub parse_frame {
	my ($self, $buffer) = @_;

	warn("PARSING FRAME\n") if DEBUG;

	my $index = index($$buffer, "\xff");

	return if $index < 0;

	my $type   = $index == 0 ? CLOSE : TEXT;
	my $length = $index - 1;
	my $bytes  = $length
			? substr(substr($$buffer, 0, $index + 1, ''), 1, $length)
			: '';

	if (DEBUG) {
		warn('TYPE: ', $type, "\n");
		warn('LENGTH: ', $length, "\n");
		if ($length) {
			warn('BYTES: ', $bytes, "\n");
		}
		else {
			warn("NOTHING\n") 
		}
	}

	# Result does compatible with Mojo::Transaction::WebSocket.
	return [1, $type, $bytes];
}

sub server_handshake {
	my ($self) = @_;

	my $req = $self->req;
	my $content = $req->content;

	# Fetch request body.
	$content->headers->content_length(length($content->leftovers));
	$content->parse_body_once();

	my $res = bless($self->res, 'MojoX::Transaction::WebSocket76::_Response');
	my $headers = $req->headers;

	$res->code(101);
	$res->message('WebSocket Protocol Handshake');
	$res->body(
		$self->_challenge(
			scalar($headers->header('Sec-WebSocket-Key1')),
			scalar($headers->header('Sec-WebSocket-Key2')),
			$req->body # Key3 data.
		)
	);

	my $url      = $req->url;
	my $scheme   = $url->to_abs->scheme eq 'https' ? 'wss' : 'ws';
	my $location = $url->to_abs->scheme($scheme)->to_string();
	my $origin   = $headers->header('Origin');
	my $protocol = $headers->sec_websocket_protocol;

	$headers = $res->headers;
	$headers->upgrade('WebSocket');
	$headers->connection('Upgrade');
	$headers->header('Sec-WebSocket-Location' => $location);
	$headers->sec_websocket_origin($origin) if $origin;
	$headers->sec_websocket_protocol($protocol) if $protocol;

	return $self;
}

sub _challenge {
	my ($self, $key1, $key2, $key3) = @_;

	return unless $key1 && $key2 && $key3;
	return md5_bytes(join('',
		pack('N', join('', $key1 =~ /(\d)/g) / ($key1 =~ tr/\ //)),
		pack('N', join('', $key2 =~ /(\d)/g) / ($key2 =~ tr/\ //)),
		$key3
	));
}


1;


package MojoX::Transaction::WebSocket76::_Response;

use Mojo::Base 'Mojo::Message::Response';


sub fix_headers {
	my ($self) = @_;

	$self->SUPER::fix_headers(@_[1 .. $#_]);
	# Suppress "Content-Length" header.
	$self->headers->remove('Content-Length');
}


1;
