
#pragma OPENCL EXTENSION cl_khr_byte_addressable_store : enable 

#define RADIX 8
#define RADICES (1 << RADIX)
#define NUM_OF_ELEMENTS_PER_WORK_ITEM RADICES
#define MASK (1 << RADIX) - 1 
__kernel
void histogramInstantiated(__global uint* unsortedData,
               __global uint* buckets,
			   __global uint* histScanBuckets,
               uint shiftCount,
               __local uint* sharedArray)
{
    size_t localId = get_local_id(0);
    size_t globalId = get_global_id(0);
    size_t groupId = get_group_id(0);
    size_t groupSize = get_local_size(0);
	size_t numOfGroups = get_num_groups(0);
    //uint local[RADICES];
    uint bucketPos = groupId * RADICES * groupSize;
    for(int i = 0; i < RADICES; ++i)
    {
        buckets[bucketPos + localId * RADICES + i] = 0;
    }

    barrier(CLK_LOCAL_MEM_FENCE);
    /* Calculate thread-histograms */

    for(int i = 0; i < NUM_OF_ELEMENTS_PER_WORK_ITEM; ++i)
    {
        uint value = unsortedData[globalId * NUM_OF_ELEMENTS_PER_WORK_ITEM + i];
        value = (value >> shiftCount) & MASK;
        buckets[bucketPos + localId * RADICES + value]++;
    }

    barrier(CLK_GLOBAL_MEM_FENCE);

    //Start First step to scan
	int sum =0;
    for(int i = 0; i < groupSize; i++)
    {
        sum = sum + buckets[bucketPos + localId + groupSize*i];
	}
    histScanBuckets[localId*numOfGroups + groupId + 1] = sum;

}
__kernel 
void scanLocalInstantiated(__global uint* buckets,
                  __global uint* histScanBuckets,
                  __local uint* localScanArray)
{
    size_t localId = get_local_id(0); 
    size_t numOfGroups = get_num_groups(0);
    size_t groupId = get_group_id(0);
    size_t groupSize = get_local_size(0);

	localScanArray[localId] = histScanBuckets[localId*numOfGroups + groupId];
	localScanArray[RADICES+localId] = 0;

    barrier(CLK_LOCAL_MEM_FENCE);
    for(int i = 0; i < RADICES; ++i)
    {
        uint bucketPos = groupId * RADICES * groupSize + i * RADICES + localId;
        uint temp = buckets[bucketPos];
        buckets[bucketPos] = localScanArray[RADICES+localId] + localScanArray[localId];
        localScanArray[RADICES+localId] += temp;
    }
}

__kernel
void permuteInstantiated(__global uint* unsortedData,
             __global uint* scanedBuckets,
             uint shiftCount,
             __local uint* sharedBuckets,
             __global uint* sortedData)
{

    size_t groupId = get_group_id(0);
    size_t localId = get_local_id(0);
    size_t globalId = get_global_id(0);
    size_t groupSize = get_local_size(0);
    
    uint bucketPos = groupId * RADICES * groupSize;
    /* Copy prescaned thread histograms to corresponding thread shared block */
    //for(int i = 0; i < RADICES; ++i)
    //{
        //uint bucketPos = groupId * RADICES * groupSize + localId * RADICES + i;
        //sharedBuckets[localId * RADICES + i] = scanedBuckets[localId * RADICES + i];
    //}

    //barrier(CLK_LOCAL_MEM_FENCE);
    
    /* Premute elements to appropriate location */
    for(int i = 0; i < RADICES; ++i)
    {
        uint value = unsortedData[globalId * RADICES + i];
        barrier(CLK_LOCAL_MEM_FENCE);
        value = (value >> shiftCount) & MASK;
        uint index = scanedBuckets[bucketPos+localId * RADICES + value];
        sortedData[index] = unsortedData[globalId * RADICES + i];
        barrier(CLK_LOCAL_MEM_FENCE);
        scanedBuckets[bucketPos+localId * RADICES + value] = index + 1;
		barrier(CLK_LOCAL_MEM_FENCE);
    }
}
