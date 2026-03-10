export default {
	async fetch(request: Request, env: any): Promise<Response> {
		const url = new URL(request.url);

		// Route aliases
		if (url.pathname === '/signing' || url.pathname === '/threshold') {
			return Response.redirect(new URL('/threshold-signing.html', url.origin).toString(), 301);
		}
		if (url.pathname === '/demo') {
			return Response.redirect(new URL('/demo-guide.html', url.origin).toString(), 301);
		}
		if (url.pathname === '/dkg' || url.pathname === '/keygen') {
			return Response.redirect(new URL('/dkg-ceremony.html', url.origin).toString(), 301);
		}
		if (url.pathname === '/p2p' || url.pathname === '/peer' || url.pathname === '/devices') {
			return Response.redirect(new URL('/device-to-device.html', url.origin).toString(), 301);
		}
		if (url.pathname === '/server' || url.pathname === '/architecture' || url.pathname === '/arch') {
			return Response.redirect(new URL('/server-architecture.html', url.origin).toString(), 301);
		}

		// Let static assets handle everything else (index.html as default)
		return env.ASSETS.fetch(request);
	},
};
