//
//  TableSearchDisplayDemoViewController.m
//  nut-demo
//
//  Created by Samuel Défago on 2/14/11.
//  Copyright 2011 Hortis. All rights reserved.
//

#import "TableSearchDisplayDemoViewController.h"

#import "DeviceFeedFilter.h"
#import "DeviceInfo.h"

static NSArray *s_data;

typedef enum {
    ScopeButtonIndexEnumBegin = 0,
    ScopeButtonIndexAll = ScopeButtonIndexEnumBegin,
    ScopeButtonIndexMusicPlayers,
    ScopeButtonIndexPhones,
    ScopeButtonIndexTablets,
    ScopeButtonIndexEnumEnd,
    ScopeButtonIndexEnumSize = ScopeButtonIndexEnumEnd - ScopeButtonIndexEnumBegin
} ScopeButtonIndex;

@interface TableSearchDisplayDemoViewController ()

@property (nonatomic, retain) HLSFeed *deviceFeed;
@property (nonatomic, retain) HLSFeedFilter *deviceFeedFilter;

- (DeviceFeedFilter *)buildDeviceFeedFilter;

@end

@implementation TableSearchDisplayDemoViewController

#pragma mark Class methods

+ (void)initialize
{
    NSMutableArray *data = [NSMutableArray array];
    [data addObject:[DeviceInfo deviceInfoWithName:@"Apple iPod" type:DeviceTypeMusicPlayer]];
    [data addObject:[DeviceInfo deviceInfoWithName:@"Apple iPod Touch" type:DeviceTypeMusicPlayer]];
    [data addObject:[DeviceInfo deviceInfoWithName:@"Apple iPod Nano" type:DeviceTypeMusicPlayer]];
    [data addObject:[DeviceInfo deviceInfoWithName:@"Sony Walkman" type:DeviceTypeMusicPlayer]];
    [data addObject:[DeviceInfo deviceInfoWithName:@"Apple iPhone 3G" type:DeviceTypePhone]];
    [data addObject:[DeviceInfo deviceInfoWithName:@"Apple iPhone 3GS" type:DeviceTypePhone]];
    [data addObject:[DeviceInfo deviceInfoWithName:@"Apple iPhone 4" type:DeviceTypePhone]];
    [data addObject:[DeviceInfo deviceInfoWithName:@"HTC Desire" type:DeviceTypePhone]];
    [data addObject:[DeviceInfo deviceInfoWithName:@"Apple iPad" type:DeviceTypeTablet]];
    [data addObject:[DeviceInfo deviceInfoWithName:@"Samsung Galaxy Tab" type:DeviceTypeTablet]];
    s_data = [[NSArray arrayWithArray:data] retain];
}

#pragma mark Object creation and destruction

- (id)init
{
    if (self = [super init]) {
        self.title = @"HLSTableSearchDisplayViewController";
        self.searchDelegate = self;
        
        self.deviceFeed = [[[HLSFeed alloc] init] autorelease];
        self.deviceFeed.entries = s_data;
    }
    return self;
}

- (void)dealloc
{
    self.deviceFeed = nil;
    self.deviceFeedFilter = nil;
    [super dealloc];
}

#pragma mark Accessors and mutators

@synthesize deviceFeed = m_deviceFeed;

@synthesize deviceFeedFilter = m_deviceFeedFilter;

#pragma mark View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.searchBar.scopeButtonTitles = [NSArray arrayWithObjects:NSLocalizedString(@"All", @"All"),
                                        NSLocalizedString(@"Music players", @"Music players"),
                                        NSLocalizedString(@"Phones", @"Phones"),
                                        NSLocalizedString(@"Tablets", @"Tablets"),
                                        nil];
}

#pragma mark Orientation management

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    if (! [super shouldAutorotateToInterfaceOrientation:toInterfaceOrientation]) {
        return NO;
    }
    
    return UIInterfaceOrientationIsPortrait(toInterfaceOrientation);
}

#pragma mark HLSTableSearchDisplayViewControllerDelegate protocol implementatio

- (void)tableSearchDisplayViewControllerWillBeginSearch:(HLSTableSearchDisplayViewController *)controller
{
    // We want a search to always open with the "All" scope button selected
    self.searchBar.selectedScopeButtonIndex = ScopeButtonIndexAll;
    
    // Create the corresponding filter
    self.deviceFeedFilter = [self buildDeviceFeedFilter];
    
    // Sync data
    [self.tableView reloadData];
}

- (BOOL)tableSearchDisplayViewController:(HLSTableSearchDisplayViewController *)controller 
        shouldReloadTableForSearchString:(NSString *)searchString
{
    // Create the corresponding filter
    self.deviceFeedFilter = [self buildDeviceFeedFilter];
    
    // Trigger a table view reload
    return YES;
}

- (BOOL)tableSearchDisplayViewController:(HLSTableSearchDisplayViewController *)controller 
         shouldReloadTableForSearchScope:(NSInteger)searchOption
{
    // Clear the filter
    self.deviceFeedFilter = [self buildDeviceFeedFilter];
    
    // Trigger a table view reload
    return YES;
}

- (BOOL)tableSearchDisplayViewControllerShouldReloadOriginalTable:(HLSTableSearchDisplayViewController *)controller
{
    // Create the corresponding filter
    self.deviceFeedFilter = nil;
    
    // Trigger a table view reload
    return YES;
}

#pragma mark UITableViewDataSource protocol implementation

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.deviceFeed countMatchingFilter:self.deviceFeedFilter];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath 
{   
    DeviceInfo *deviceInfo = [self.deviceFeed entryAtIndex:indexPath.row matchingFilter:self.deviceFeedFilter];
    HLSTableViewCell *cell = HLS_TABLE_VIEW_CELL(HLSTableViewCell, tableView);
    cell.textLabel.text = deviceInfo.name;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

#pragma mark Creating the search filter

- (DeviceFeedFilter *)buildDeviceFeedFilter
{
    DeviceFeedFilter *filter = [[[DeviceFeedFilter alloc] initWithFeed:self.deviceFeed] autorelease];
    filter.pattern = self.searchBar.text;
    
    switch (self.searchBar.selectedScopeButtonIndex) {            
        case ScopeButtonIndexMusicPlayers: {
            filter.type = DeviceTypeMusicPlayer;
            break;
        }
            
        case ScopeButtonIndexPhones: {
            filter.type = DeviceTypePhone;            
            break;
        }
            
        case ScopeButtonIndexTablets: {
            filter.type = DeviceTypeTablet;
            break;
        }
            
        case ScopeButtonIndexAll:
        default: {
            filter.type = DeviceTypeAll;
            break;
        }
    }
        
    return filter;
}

@end
