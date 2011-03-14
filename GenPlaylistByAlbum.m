//
// Nope, this is pretty much a quick-n-dirty hack. I hadn't though about all the problems it may have.
// 
// Jim, http://nukethemfromorbit.com/
//

#import <Foundation/Foundation.h>
#import <ScriptingBridge/ScriptingBridge.h>
#import "iTunes.h"

enum {
	B = 0,
	K,
	M,
	G
} typedef SizeType;

static inline NSInteger randomWithClamps( NSInteger _min, NSInteger _max ) { 
	return( (NSInteger)(((_max - _min + 1) * ((double)random() / (double)RAND_MAX )) + _min) );
}

void _help( const char *errorMsg );
double convertSizeFromString( NSString *input, SizeType tgt );
double convertSize( double input, SizeType src, SizeType tgt );

int main (int argc, const char * argv[]) 
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

	srandomdev();

	NSString *playlistName = @"Random by Album";
	double maxSize = 268435456; // 256MB
	BOOL quiet = NO;

	NSArray *args = [[NSProcessInfo processInfo] arguments];
	int x;
	for( x=1; x<[args count]; x++ ) {
		NSString *a = [args objectAtIndex:x];
		if( [a hasPrefix:@"-"] ) {
			NSString *key = [a stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
			
			if( [key isEqualToString:@"name"] ) {
				playlistName = [args objectAtIndex:x+1];;
				x++;
			}
			else if( [key isEqualToString:@"maxSize"] ) {
				maxSize = convertSizeFromString( [args objectAtIndex:x+1], B );
				x++;
			}
			else if( [key isEqualToString:@"quiet"] ) {
				quiet = YES;
			}
			else if( [key isEqualToString:@"help"] || [key isEqualToString:@"h"] ) {
				_help( NULL );
			}
			else {
				_help( [[NSString stringWithFormat:@"Unknown argument \'%@\'", key] UTF8String] );
			}
		}
	}
	
	iTunesPlaylist *libraryPlaylist = nil;
	iTunesSource *librarySource = nil;
	iTunesApplication *iTunes = [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
	
	// Find our library objects
	for( iTunesSource *src in [iTunes sources] ) {
		if( [src kind] == iTunesESrcLibrary ) {
			librarySource = src;
			for( iTunesPlaylist *playlist in [src playlists] ) {
				if( [[playlist name] isEqualToString:@"Library"] ) {
					libraryPlaylist = playlist;
					break;
				}
			}
			
			break;
		}
	}
	
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:1000];
	if( libraryPlaylist ) {
		NSArray *tracks = [[libraryPlaylist tracks] get];
		NSUInteger trackCount = 0;

		// Gather up what tracks belong to which albums
		for( iTunesTrack *aTrack in tracks ) {
			if( [dict objectForKey:aTrack.album] ) {
				NSMutableDictionary *attrs = [dict objectForKey:aTrack.album];
				[attrs setObject:[NSNumber numberWithInteger:aTrack.size + [[attrs objectForKey:@"albumSize"] integerValue]] forKey:@"albumSize"];
				[[attrs objectForKey:@"tracks"] addObject:aTrack];
			}
			else {
				NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:aTrack.size], @"albumSize",
											  [NSMutableArray arrayWithObject:aTrack], @"tracks",
											  aTrack.album, @"albumName",
											  nil];
				[dict setObject:attrs forKey:aTrack.album];
			}
			
			trackCount++;
			
			if( !quiet ) {
				if( (trackCount % 1000) == 0 ) {
					printf( "passed %lu tracks\n", trackCount );
				}
			}
		}

		// Make a new playlist
		NSDictionary *propertiesDict = [NSDictionary dictionaryWithObjectsAndKeys:playlistName, @"name",[NSNumber numberWithBool:NO], @"shuffle", nil];
		SBObject *newPlaylist = [[[iTunes classForScriptingClass:@"playlist"] alloc] initWithProperties:propertiesDict];
		[[librarySource userPlaylists] insertObject:newPlaylist atIndex:0];

		NSMutableArray *keys = [[dict allKeys] mutableCopy];
		NSUInteger accumulatedSize = 0;
		
		// Add tracks to the playlist until we've reached our desired size
		do {
			NSInteger _idx = randomWithClamps(0, [keys count]-1);
			NSString *k = [keys objectAtIndex:_idx];
			NSMutableDictionary *album = [dict objectForKey:k];
			
			accumulatedSize += [[album objectForKey:@"albumSize"] integerValue];
			if( !quiet ) {
				printf( "adding %s, accumulatedSize at %.2f\n", [[album objectForKey:@"albumName"] UTF8String], convertSize( accumulatedSize, B, M ) );
			}
			
			for( iTunesTrack *aTrack in [album objectForKey:@"tracks"] ) {
				[aTrack duplicateTo:newPlaylist];
			}
			
			[keys removeObjectAtIndex:_idx];
			
		} while( accumulatedSize < maxSize );
	}

    [pool drain];
    return( 0 );
}

double convertSizeFromString( NSString *input, SizeType tgt )
{
	NSRange r = [input rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"bBkKmMgG"]];
	SizeType src = B;
	double inputNumber = [input doubleValue];;
	if( r.location != NSNotFound ) {
		NSString *sizeChar = [[input substringWithRange:r] uppercaseString];
		if( [sizeChar isEqualToString:@"B"] ) {
			src = B;
		}
		else if( [sizeChar isEqualToString:@"K"] ) {
			src = K;
		}
		else if( [sizeChar isEqualToString:@"M"] ) {
			src = M;
		}
		else if( [sizeChar isEqualToString:@"G"] ) {
			src = G;
		}
	}

	return( convertSize( inputNumber, src, tgt ) );
}

double convertSize( double input, SizeType src, SizeType tgt )
{
	int x;
	if( src != tgt ) {
		// Smaller unit to a larger unit
		if( src < tgt ) {
			for( x=0; x<(tgt-src); x++ ) {
				input /= 1024.0;
			}
		}
		else {
			for( x=0; x<(src-tgt); x++ ) {
				input *= 1024.0;
			}
		}
	}

	return( input );
}


void _help( const char *errorMsg )
{
	if( errorMsg ) {
		printf( "\n%s\n\n", errorMsg );
	}

	printf( "Usage: GenPlaylistByAlbum [-name nameOfPlaylist] [-maxSize size{BKMG}] [-quiet] [-h]\n" );
	printf( "\tName defaults to 'Random by Album', maximum size of 256MB\n" );
	printf( "\tTo denote a size, use ### followed by either B for bytes, K for kilobytes, M for megabytes or G for gigabytes\n" );
	printf( "\n\tTo make a playlist called 'MyPlaylist' 700MB in size:\n" );
	printf( "\t\tGenPlaylistByAlbum -name MyPlaylist -maxSize 700M\n" );
	
	exit(0);
}
